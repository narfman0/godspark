#!/usr/bin/env python3
"""Copy rigged monsters and their props from monster-forge into assets/ (stdlib only).

    python3 -I tools/sync_monsters.py --all                 # every rigged monster with clips + every prop
    python3 -I tools/sync_monsters.py --ids wolf harpy      # these monsters + the props they wield
    python3 -I tools/sync_monsters.py --props               # every prop (or --props scimitar shield)
    python3 -I tools/sync_monsters.py --all --forge ~/workspace/monster-forge --source srd-5.2.1

Copies only what the game loads: model_rigged.glb (LOD0, textures embedded),
model_rigged_lod<k>.glb (geometry only, they use LOD0's material) and anims/<clip>.glb, and
writes a trimmed monster.json (id, name, scale_m, body_plan, sockets, clips, lods, plus
wields / shield from data/registry/<source>.json, rider_height_m from the manifest or
data/overrides/<source>/<id>.json, swarm_unit from the manifest when the swarm was made as
one unit). Props (out/props/<id>/, already in prop
space) go to assets/props/<id>/: model.glb, model_lod<k>.glb, lods.json, manifest.json.
Never model_hi.glb, model_raw.glb, PNGs or paint/. Idempotent: files are compared by content, unchanged files are
left alone, files the source no longer has are removed. Monsters without a rig are skipped,
and --all also skips rigged monsters that have no clips yet.
Ported from godot-dnd (docs/monsters.md there). Godspark additions:
  --registry   writes data/looks_creatures.json (slug -> size, type, body plan, scale_m,
               speeds for all SRD monsters) from the forge registry. It is committed: the
               looks resolver uses it to give unlisted slugs a by-type / by-size body.
  .gdignore    is written into assets/monsters and assets/props so the editor never imports
               them (the game loads the GLBs at runtime with GLTFDocument).
When ../monster-forge is missing, it says so and exits 0: the game runs without monsters.
See docs/tracks/assets.md.

HTTP mode (docs/tracks/forge-art.md): the forge machine's viewer (monster-forge tools/viewer.py)
serves /api/index.json and out/ read-only, so no checkout of the 55 GB out/ is needed:

    python3 -I tools/sync_monsters.py --http --all            # every usable monster + every prop
    python3 -I tools/sync_monsters.py --http --ids wolf ape   # these (+ the props they wield)
    python3 -I tools/sync_monsters.py --http --all --dry-run  # what would change, and its size
    python3 -I tools/sync_monsters.py --http URL --all --lod 0 --prune

"Usable" is decided from the index: rig and anim stages done, an idle clip and a move clip
(walk / fly / swim / run / move / hover), not listed in data/forge_quarantine.json (the slugs
known bad today, with a reason; --force ignores it). Each file is fetched only when its size or
Last-Modified differs from what the last sync recorded; GLBs are checked (magic, JSON chunk,
LOD0 has a skin) in a temp file before they replace anything, so a broken upstream re-roll
keeps the previous copy. monster.json records where it came from: forge.url, the index's
generated_at, the manifest's sha256 and each file's bytes + Last-Modified, so the next run (or
a person) can tell what changed. Every run writes assets/monsters/_sync.json: status per id
(added, updated, unchanged, skipped + reason, quarantined, failed). Sequential and polite:
one request at a time. The wielded props come from the registry of a local monster-forge
checkout when there is one (read only), else monsters wield nothing.
"""
import argparse
import email.utils
import hashlib
import html.parser
import json
import os
import shutil
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "monsters"
PROPS_DEST = ROOT / "assets" / "props"
# A sibling checkout; from a worktree (../godspark-wt/<name>) it is one level further up.
DEFAULT_FORGE = Path(os.environ.get("MONSTER_FORGE") or next(
    (p for p in (ROOT.parent / "monster-forge", ROOT.parent.parent / "monster-forge") if p.is_dir()),
    ROOT.parent / "monster-forge"))
DEFAULT_URL = os.environ.get("MONSTER_FORGE_URL", "http://192.168.1.12:8787")
QUARANTINE = ROOT / "data" / "forge_quarantine.json"
# A creature needs idle and one of these to be shown (view/actors/forge_monster.gd MOVE_CLIPS).
MOVE_CLIPS = ("walk", "run", "move", "swim", "fly", "hover")


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def glb_json(p: Path) -> dict:
    with p.open("rb") as f:
        head = f.read(20)
        if head[:4] != b"glTF":
            raise ValueError(f"{p} is not a GLB")
        n = struct.unpack("<I", head[12:16])[0]
        return json.loads(f.read(n))


def glb_tris(p: Path) -> int:
    j = glb_json(p)
    tris = 0
    for m in j.get("meshes", []):
        for prim in m["primitives"]:
            if "indices" in prim:
                tris += j["accessors"][prim["indices"]]["count"] // 3
            else:
                tris += j["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
    return tris


def wanted_files(src: Path) -> dict[str, Path]:
    """Relative destination path -> source file."""
    files = {"model_rigged.glb": src / "model_rigged.glb"}
    for p in sorted(src.glob("model_rigged_lod*.glb")):
        files[p.name] = p
    for p in sorted((src / "anims").glob("*.glb")):
        files[f"anims/{p.name}"] = p
    return files


def registry(forge: Path, source: str) -> dict:
    """id -> registry record (empty if the registry is missing)."""
    p = forge / "data" / "registry" / f"{source}.json"
    if not p.exists():
        return {}
    r = json.loads(p.read_text())
    recs = r if isinstance(r, list) else r.get("monsters", r)
    recs = recs if isinstance(recs, list) else list(recs.values())
    return {m["id"]: m for m in recs if isinstance(m, dict) and "id" in m}


def override(forge: Path, source: str, mid: str) -> dict:
    """data/overrides/<source>/<id>.json (empty if missing or unreadable)."""
    p = forge / "data" / "overrides" / source / f"{mid}.json"
    try:
        o = json.loads(p.read_text())
    except (OSError, ValueError):
        return {}
    return o if isinstance(o, dict) else {}


def monster_json(src: Path, files: dict[str, Path], rec: dict, ov: dict | None = None) -> dict:
    return monster_doc(json.loads((src / "manifest.json").read_text()), files, rec, ov)


def monster_doc(man: dict, files: dict[str, Path], rec: dict, ov: dict | None = None) -> dict:
    """The trimmed monster.json from a forge manifest and the GLBs at hand (rel -> path)."""
    rig = man.get("rig") or {}
    lods = {"0": {"file": "model_rigged.glb", "tris": glb_tris(files["model_rigged.glb"])}}
    for name in files:
        if name.startswith("model_rigged_lod"):
            k = name[len("model_rigged_lod"):-len(".glb")]
            lods[k] = {"file": name, "tris": glb_tris(files[name])}
    # The rig stage renames each socket bone to the socket name in the GLB; the manifest
    # maps socket -> the bone it was derived from (kept for reference).
    sockets = {s: {"bone": s, "from": b} for s, b in sorted(rig.get("sockets", {}).items())}
    ov = ov or {}
    out = {
        "id": man["id"],
        "name": man.get("name", man["id"]),
        "source": man.get("source"),
        "scale_m": man.get("scale_m"),
        "body_plan": man.get("body_plan"),
        "sockets": sockets,
        "clips": sorted(Path(n).stem for n in files if n.startswith("anims/")),
        "lods": dict(sorted(lods.items(), key=lambda kv: int(kv[0]))),
        "joints": rig.get("joints"),
        "wields": rec.get("wields", []),
        "shield": bool(rec.get("shield", False)),
    }
    # Props are sized for a 1.8 m wielder: centauroids / merfolk-naga carry the rider's height
    # (override rider_height_m, docs/equipment.md "Prop space"); the game scales props by it.
    rh = man.get("rider_height_m", ov.get("rider_height_m", rec.get("rider_height_m")))
    if rh is not None:
        out["rider_height_m"] = rh
    # A swarm made as ONE unit (monster-forge docs/references.md "Swarm units"): the model is a
    # single unit at swarm_unit.scale_m, the game multiplies it over swarm_unit.swarm.scale_m.
    if man.get("swarm_unit"):
        out["swarm_unit"] = man["swarm_unit"]
    return out


def copy_files(files: dict[str, Path], dest: Path) -> list[str]:
    changes = []
    dest.mkdir(parents=True, exist_ok=True)
    for rel, sp in files.items():
        dp = dest / rel
        if dp.exists() and dp.stat().st_size == sp.stat().st_size and digest(dp) == digest(sp):
            continue
        dp.parent.mkdir(parents=True, exist_ok=True)
        tmp = dp.with_suffix(dp.suffix + ".tmp")
        shutil.copyfile(sp, tmp)
        changes.append(("updated " if dp.exists() else "added   ") + rel)
        tmp.replace(dp)
    return changes


def sync_one(src: Path, dest: Path, rec: dict, ov: dict | None = None) -> list[str]:
    files = wanted_files(src)
    changes = copy_files(files, dest)
    # Remove GLBs the source no longer has (and Godot's .import sidecars for them).
    for dp in sorted(list(dest.glob("*.glb")) + list(dest.glob("anims/*.glb"))):
        rel = dp.relative_to(dest).as_posix()
        if rel not in files:
            dp.unlink()
            Path(str(dp) + ".import").unlink(missing_ok=True)
            changes.append("removed " + rel)
    text = json.dumps(monster_json(src, files, rec, ov), indent=1) + "\n"
    mj = dest / "monster.json"
    if not mj.exists() or mj.read_text() != text:
        changes.append(("updated " if mj.exists() else "added   ") + "monster.json")
        mj.write_text(text)
    return changes


def sync_prop(src: Path, dest: Path) -> list[str]:
    files = {"model.glb": src / "model.glb", "manifest.json": src / "manifest.json"}
    if (src / "lods.json").exists():
        files["lods.json"] = src / "lods.json"
    for p in sorted(src.glob("model_lod*.glb")):
        files[p.name] = p
    changes = copy_files(files, dest)
    for dp in sorted(dest.glob("model_lod*.glb")):
        if dp.name not in files:
            dp.unlink()
            Path(str(dp) + ".import").unlink(missing_ok=True)
            changes.append("removed " + dp.name)
    return changes


def sync_props(prop_root: Path, ids: list[str], dest: Path) -> int:
    failed = 0
    for pid in ids:
        src = prop_root / pid
        if not (src / "model.glb").exists() or not (src / "manifest.json").exists():
            print(f"prop {pid}: skipped (no model.glb or manifest.json in {src})")
            failed += 1
            continue
        changes = sync_prop(src, dest / pid)
        print(f"prop {pid}: " + ("unchanged" if not changes else f"{len(changes)} change(s)"))
        for c in changes:
            print("  " + c)
    return failed


# --- HTTP mode ------------------------------------------------------------------------------

def load_quarantine(p: Path = QUARANTINE) -> dict[str, str]:
    """slug -> reason, from data/forge_quarantine.json ({} when missing or unreadable)."""
    try:
        q = json.loads(p.read_text()).get("monsters", {})
    except (OSError, ValueError, AttributeError):
        return {}
    return {str(k): str(v.get("reason", v) if isinstance(v, dict) else v) for k, v in q.items()} if isinstance(q, dict) else {}


def index_clips(entry: dict) -> list[str]:
    """The clips that exist as anims/<clip>.glb for an index entry."""
    clips = entry.get("external_clips")
    if clips is None:
        clips = entry.get("found_clips") or []
    return sorted(str(c) for c in clips)


def verdict(entry: dict, quarantine: dict[str, str], force: bool = False) -> tuple[bool, str, list[str]]:
    """(usable, why not, warnings) for an index entry. Pure."""
    st = entry.get("stages") or {}
    warn = []
    if not st.get("rig"):
        return False, "no rig yet", warn
    if not st.get("anim"):
        return False, "no anims yet", warn
    clips = index_clips(entry)
    if "idle" not in clips:
        return False, "no idle clip", warn
    if not any(c in clips for c in MOVE_CLIPS):
        return False, "no move clip (walk, fly, swim...)", warn
    if not force and entry.get("id") in quarantine:
        return False, "quarantined: " + quarantine[entry["id"]], warn
    if entry.get("missing_clips"):
        warn.append("missing clips " + ",".join(entry["missing_clips"]))
    rq = entry.get("rig_quality") or {}
    if rq.get("problems"):
        warn.append("rig_quality " + ",".join(str(x) for x in rq["problems"]))
    if (rq.get("facing") or {}).get("ok") is False:
        warn.append("facing not ok")
    if entry.get("errors"):
        warn.append(f"{entry['errors']} forge error(s)")
    return True, "", warn


def http_plan(entry: dict, lod_max: int) -> dict[str, str]:
    """Relative destination path -> server path, for an index entry. Pure."""
    d = str(entry.get("dir") or f"/out/{entry.get('source', 'srd-5.2.1')}/{entry['id']}/")
    d = d if d.endswith("/") else d + "/"
    lods = entry.get("lods") or {}
    files = {"model_rigged.glb": d + str((lods.get("0") or {}).get("file") or "model_rigged.glb")}
    for k in sorted(lods, key=lambda x: int(x)):
        if 0 < int(k) <= lod_max and lods[k].get("file"):
            files[str(lods[k]["file"])] = d + str(lods[k]["file"])
    for c in index_clips(entry):
        files[f"anims/{c}.glb"] = f"{d}anims/{c}.glb"
    return files


def glb_check(p: Path, need_skin: bool = False, need_anim: bool = False) -> str:
    """'' when the GLB looks usable, else why not."""
    try:
        j = glb_json(p)
    except (OSError, ValueError, struct.error) as e:
        return f"unreadable GLB ({e})"
    if need_skin and not j.get("skins"):
        return "no skin (skeleton)"
    if not j.get("meshes") and not need_anim:
        return "no mesh"
    if need_anim and not any(a.get("channels") for a in j.get("animations", [])):
        return "no animation channels"
    return ""


class Forge:
    """The forge viewer over HTTP: one request at a time, a couple of retries."""

    def __init__(self, base: str, timeout: float = 60.0, retries: int = 2):
        self.base = base.rstrip("/")
        self.timeout = timeout
        self.retries = retries
        self.requests = 0
        self.bytes = 0

    def url(self, path: str) -> str:
        return self.base + "/" + urllib.parse.quote(path.lstrip("/"))

    def _open(self, path: str, method: str = "GET"):
        last = None
        for i in range(self.retries + 1):
            try:
                self.requests += 1
                req = urllib.request.Request(self.url(path), method=method,
                                             headers={"User-Agent": "godspark-sync/1"})
                return urllib.request.urlopen(req, timeout=self.timeout)
            except urllib.error.HTTPError:
                raise
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                last = e
                time.sleep(1.0 + 2.0 * i)
        raise last

    def get(self, path: str) -> bytes:
        with self._open(path) as r:
            b = r.read()
        self.bytes += len(b)
        return b

    def head(self, path: str) -> dict | None:
        """{bytes, modified} or None when the server has no such file."""
        try:
            with self._open(path, "HEAD") as r:
                return {"bytes": int(r.headers.get("Content-Length") or -1),
                        "modified": r.headers.get("Last-Modified") or ""}
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise

    def fetch(self, path: str, dest: Path) -> dict:
        """Streams a file to dest; raises when the length is short."""
        dest.parent.mkdir(parents=True, exist_ok=True)
        with self._open(path) as r, dest.open("wb") as f:
            want = int(r.headers.get("Content-Length") or -1)
            meta = {"bytes": want, "modified": r.headers.get("Last-Modified") or ""}
            n = 0
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                n += len(chunk)
        self.bytes += n
        if want >= 0 and n != want:
            raise ValueError(f"{path}: got {n} of {want} bytes")
        meta["bytes"] = n
        return meta

    def listing(self, path: str) -> list[str]:
        """Entries of a directory listing page (names; directories end in '/')."""
        class P(html.parser.HTMLParser):
            def __init__(self):
                super().__init__()
                self.out = []

            def handle_starttag(self, tag, attrs):
                h = dict(attrs).get("href")
                if tag == "a" and h and not h.startswith(("?", "/", "..")):
                    self.out.append(urllib.parse.unquote(h))
        p = P()
        p.feed(self.get(path).decode("utf-8", "replace"))
        return p.out


def _recorded(dest: Path, name: str = "monster.json") -> dict:
    try:
        return json.loads((dest / name).read_text()).get("forge", {}).get("files", {})
    except (OSError, ValueError, AttributeError):
        return {}


def _stage(forge: Forge, plan: dict[str, str], dest: Path, rec: dict, check) -> tuple[dict, list, list, int]:
    """HEAD every planned file, fetch what changed into dest/.incoming. Returns
    (file meta by rel, rels fetched, warnings, bytes to fetch). check(rel, path) -> '' or why."""
    meta, fetched, warn, size = {}, [], [], 0
    inc = dest / ".incoming"
    for rel, sp in plan.items():
        h = forge.head(sp)
        if h is None:
            warn.append(f"{rel}: listed but not served")
            continue
        dp = dest / rel
        old = rec.get(rel) or {}
        if dp.exists() and dp.stat().st_size == h["bytes"] and old.get("modified") == h["modified"]:
            meta[rel] = {"bytes": h["bytes"], "modified": h["modified"]}
            continue
        size += h["bytes"]
        if check is None:          # dry run
            meta[rel] = h
            fetched.append(rel)
            continue
        tp = inc / rel
        meta[rel] = forge.fetch(sp, tp)
        why = check(rel, tp)
        if why:
            warn.append(f"{rel}: {why}")
            tp.unlink(missing_ok=True)
            del meta[rel]
            continue
        fetched.append(rel)
    return meta, fetched, warn, size


def _commit(dest: Path, fetched: list[str], keep: set[str], glob_pats: tuple[str, ...]) -> list[str]:
    """Move staged files in, remove files of these patterns that are no longer wanted."""
    changes = []
    inc = dest / ".incoming"
    for rel in fetched:
        dp = dest / rel
        dp.parent.mkdir(parents=True, exist_ok=True)
        changes.append(("updated " if dp.exists() else "added   ") + rel)
        (inc / rel).replace(dp)
    shutil.rmtree(inc, ignore_errors=True)
    for pat in glob_pats:
        for dp in sorted(dest.glob(pat)):
            rel = dp.relative_to(dest).as_posix()
            if rel not in keep:
                dp.unlink()
                changes.append("removed " + rel)
    return changes


def sync_one_http(forge: Forge, entry: dict, dest: Path, rec: dict, lod_max: int,
                  dry_run: bool = False) -> dict:
    """One monster. Returns {status, changes, warnings, bytes}; status added | updated |
    unchanged | failed | would-fetch."""
    mid = entry["id"]
    plan = http_plan(entry, lod_max)
    recorded = _recorded(dest)
    man_bytes = forge.get(entry.get("dir", f"/out/srd-5.2.1/{mid}/") + "manifest.json")
    man = json.loads(man_bytes)
    man_sha = hashlib.sha256(man_bytes).hexdigest()

    def check(rel: str, p: Path) -> str:
        if rel == "model_rigged.glb":
            return glb_check(p, need_skin=True)
        if rel.startswith("anims/"):
            return glb_check(p, need_anim=True)
        return glb_check(p, need_skin=True)

    if dry_run:
        meta, fetched, warn, size = _stage(forge, plan, dest, recorded, None)
        return {"status": "would-fetch" if fetched else "unchanged", "changes": fetched, "warnings": warn, "bytes": size}
    try:
        meta, fetched, warn, size = _stage(forge, plan, dest, recorded, check)
    except (OSError, ValueError, urllib.error.URLError) as e:
        shutil.rmtree(dest / ".incoming", ignore_errors=True)
        return {"status": "failed", "changes": [], "warnings": [str(e)], "bytes": 0}
    if "model_rigged.glb" not in meta:
        shutil.rmtree(dest / ".incoming", ignore_errors=True)
        why = next((w for w in warn if w.startswith("model_rigged.glb")), "model_rigged.glb missing")
        return {"status": "failed", "changes": [], "warnings": [why + (" (kept the previous copy)" if (dest / "monster.json").exists() else "")], "bytes": size}
    clips = [r for r in meta if r.startswith("anims/")]
    if not any(Path(r).stem == "idle" for r in clips) or not any(Path(r).stem in MOVE_CLIPS for r in clips):
        shutil.rmtree(dest / ".incoming", ignore_errors=True)
        return {"status": "failed", "changes": [], "warnings": warn + ["no usable idle or move clip"], "bytes": size}
    mj = dest / "monster.json"
    existed = mj.exists()
    if fetched and existed:
        mj.unlink()          # never a monster.json that names half-replaced files
    changes = _commit(dest, fetched, set(meta), ("*.glb", "anims/*.glb"))
    files = {rel: dest / rel for rel in meta}
    ov = {"rider_height_m": entry["rider_height_m"]} if entry.get("rider_height_m") is not None else {}
    doc = monster_doc(man, files, rec, ov)
    doc["forge"] = {"url": forge.base, "manifest_sha256": man_sha,
                    "files": {k: meta[k] for k in sorted(meta)}}
    q = entry.get("rig_quality") or {}
    if q.get("problems") or entry.get("missing_clips"):
        doc["forge"]["flags"] = {"rig_problems": q.get("problems", []), "missing_clips": entry.get("missing_clips", [])}
    text = json.dumps(doc, indent=1) + "\n"
    if not mj.exists() or mj.read_text() != text:
        if mj.exists():
            changes.append("updated monster.json")
        mj.write_text(text)
    status = "unchanged" if not changes else ("added" if not existed else "updated")
    return {"status": status, "changes": changes, "warnings": warn, "bytes": size}


def sync_prop_http(forge: Forge, pid: str, dest: Path, lod_max: int, dry_run: bool = False) -> dict:
    d = f"/out/props/{pid}/"
    try:
        lods = json.loads(forge.get(d + "lods.json")).get("lods", {})
    except urllib.error.HTTPError:
        lods = {}
    plan = {"model.glb": d + "model.glb", "manifest.json": d + "manifest.json"}
    if lods:
        plan["lods.json"] = d + "lods.json"
    for k, v in lods.items():
        if 0 < int(k) <= lod_max and v.get("file"):
            plan[str(v["file"])] = d + str(v["file"])
    side = dest / "_forge.json"
    recorded = _recorded(dest, "_forge.json")
    chk = None if dry_run else (lambda rel, p: glb_check(p) if rel.endswith(".glb") else "")
    try:
        meta, fetched, warn, size = _stage(forge, plan, dest, recorded, chk)
    except (OSError, ValueError, urllib.error.URLError) as e:
        shutil.rmtree(dest / ".incoming", ignore_errors=True)
        return {"status": "failed", "changes": [], "warnings": [str(e)], "bytes": 0}
    if dry_run:
        return {"status": "would-fetch" if fetched else "unchanged", "changes": fetched, "warnings": warn, "bytes": size}
    if "model.glb" not in meta:
        shutil.rmtree(dest / ".incoming", ignore_errors=True)
        return {"status": "failed", "changes": [], "warnings": warn or ["model.glb missing"], "bytes": size}
    existed = (dest / "model.glb").exists()
    changes = _commit(dest, fetched, set(meta), ("model_lod*.glb",))
    text = json.dumps({"forge": {"url": forge.base, "files": {k: meta[k] for k in sorted(meta)}}}, indent=1) + "\n"
    if not side.exists() or side.read_text() != text:
        side.write_text(text)
    status = "unchanged" if not changes else ("added" if not existed else "updated")
    return {"status": status, "changes": changes, "warnings": warn, "bytes": size}


def human(n: float) -> str:
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            return f"{n:.1f} {u}" if u != "B" else f"{int(n)} B"
        n /= 1024
    return str(n)


def run_http(a) -> int:
    forge = Forge(a.http)
    t0 = time.time()
    try:
        idx = json.loads(forge.get("/api/index.json"))
    except (OSError, ValueError, urllib.error.URLError) as e:
        print(f"monster-forge viewer not reachable at {forge.base} ({e}): nothing synced "
              "(the game uses stand-ins).")
        return 0
    entries = {m["id"]: m for m in idx.get("monsters", []) if isinstance(m, dict) and "id" in m}
    quar = load_quarantine()
    reg = registry(a.forge.expanduser(), a.source) if a.forge.expanduser().is_dir() else {}
    report = {"url": forge.base, "index_generated_at": idx.get("generated_at"), "source": idx.get("source"),
              "lod_max": a.lod, "dry_run": a.dry_run, "monsters": {}, "props": {}}
    if not a.dry_run:
        for d in (a.dest, a.props_dest):
            d.mkdir(parents=True, exist_ok=True)
            (d / ".gdignore").touch()
    ids: list[str] = []
    if a.props is None:
        want = a.ids if a.ids else sorted(entries)
        for mid in want:
            e = entries.get(mid)
            if e is None:
                print(f"{mid}: not in the forge index")
                report["monsters"][mid] = {"status": "skipped", "why": "not in the index"}
                continue
            ok, why, warn = verdict(e, quar, a.force)
            if not ok:
                if a.ids or why.startswith("quarantined") or e["stages"].get("rig"):
                    print(f"{mid}: skipped ({why})")
                report["monsters"][mid] = {"status": "quarantined" if why.startswith("quarantined") else "skipped", "why": why}
                continue
            ids.append(mid)
        if a.all and a.dest.is_dir():
            for p in sorted(a.dest.iterdir()):
                if (p / "monster.json").exists() and p.name not in ids:
                    if a.prune and not a.dry_run:
                        shutil.rmtree(p)
                        print(f"{p.name}: removed (not usable upstream: {report['monsters'].get(p.name, {}).get('why', 'gone')})")
                    else:
                        print(f"{p.name}: kept (not usable upstream right now; --prune removes it)")
        total = 0
        for i, mid in enumerate(ids):
            r = sync_one_http(forge, entries[mid], a.dest / mid, reg.get(mid, {}), a.lod, a.dry_run)
            r["warnings"] = verdict(entries[mid], quar, a.force)[2] + r["warnings"]
            total += r["bytes"]
            line = f"[{i + 1}/{len(ids)}] {mid}: {r['status']}"
            if r["changes"]:
                line += f" ({len(r['changes'])} file(s), {human(r['bytes'])})"
            print(line)
            if a.verbose:
                for c in r["changes"]:
                    print("  " + c)
            for w in r["warnings"]:
                print("  ! " + w)
            report["monsters"][mid] = {k: v for k, v in r.items() if k != "changes"} | {"files": len(r["changes"])}
        report["bytes"] = total
    props: list[str] = []
    if a.props is not None:
        props = a.props or []
    elif a.all:
        props = []
    else:
        props = sorted({w for mid in ids for w in reg.get(mid, {}).get("wields", [])})
    if a.all or (a.props is not None and not a.props):
        try:
            props = props or sorted(n.rstrip("/") for n in forge.listing("/out/props/") if n.endswith("/"))
        except (OSError, urllib.error.URLError) as e:
            print(f"props: listing failed ({e})")
    for pid in props:
        r = sync_prop_http(forge, pid, a.props_dest / pid, a.lod, a.dry_run)
        print(f"prop {pid}: {r['status']}" + (f" ({len(r['changes'])} file(s), {human(r['bytes'])})" if r["changes"] else ""))
        for w in r["warnings"]:
            print("  ! " + w)
        report["props"][pid] = {k: v for k, v in r.items() if k != "changes"}
    counts: dict[str, int] = {}
    for r in list(report["monsters"].values()) + list(report["props"].values()):
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    report["counts"] = counts
    report["seconds"] = round(time.time() - t0, 1)
    report["requests"] = forge.requests
    report["downloaded"] = forge.bytes
    print(f"done in {report['seconds']} s: {counts}; {forge.requests} requests, {human(forge.bytes)} downloaded"
          + (f", {human(report.get('bytes', 0))} would be fetched" if a.dry_run else ""))
    if not a.dry_run and a.dest.is_dir():
        (a.dest / "_sync.json").write_text(json.dumps(report, indent=1) + "\n")
    return 1 if counts.get("failed") else 0


def write_registry(forge: Path, source: str) -> int:
    reg = registry(forge, source)
    if not reg:
        print(f"no registry at {forge}/data/registry/{source}.json", file=sys.stderr)
        return 2
    rows = {}
    for mid in sorted(reg):
        m = reg[mid]
        rows[mid] = {"name": m.get("name", mid), "size": m.get("size", "medium"), "type": m.get("type", ""),
                     "plan": m.get("body_plan", ""), "scale_m": m.get("scale_m"),
                     "speeds": m.get("speeds", {})}
    out = ROOT / "data" / "looks_creatures.json"
    doc = {"_comment": "Generated by tools/sync_monsters.py --registry from monster-forge's registry "
           f"({source}). Look metadata per SRD monster slug: size, creature type, body plan, "
           "height scale in metres, speeds (ft). Used by view/actors/looks.gd for by-type and "
           "by-size fallbacks. Do not edit by hand.", "source": source, "creatures": rows}
    lines = [f' {json.dumps(k)}: {json.dumps(v, separators=(",", ":"))}' for k, v in rows.items()]
    head = json.dumps({k: v for k, v in doc.items() if k != "creatures"}, indent=1)[:-2]
    out.write_text(head + ',\n "creatures": {\n' + ",\n".join(lines) + "\n }\n}\n")
    print(f"wrote {out.relative_to(ROOT)}: {len(rows)} creatures")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--ids", nargs="+", metavar="ID", help="these monsters and the props they wield")
    g.add_argument("--all", action="store_true", help="every monster with model_rigged.glb and clips, every prop")
    g.add_argument("--props", nargs="*", metavar="PROP", help="props only (all when no id is given)")
    g.add_argument("--registry", action="store_true", help="write data/looks_creatures.json from the registry")
    ap.add_argument("--forge", type=Path, default=DEFAULT_FORGE, help="monster-forge checkout")
    ap.add_argument("--source", default="srd-5.2.1")
    ap.add_argument("--dest", type=Path, default=DEST)
    ap.add_argument("--props-dest", type=Path, default=PROPS_DEST)
    ap.add_argument("--http", nargs="?", const=DEFAULT_URL, metavar="URL",
                    help=f"fetch from the forge viewer over HTTP (default {DEFAULT_URL}, env MONSTER_FORGE_URL)")
    ap.add_argument("--lod", type=int, default=3, choices=range(0, 4), help="HTTP: highest LOD to fetch (default 3)")
    ap.add_argument("--dry-run", action="store_true", help="HTTP: report what would change and its size, write nothing")
    ap.add_argument("--prune", action="store_true", help="HTTP --all: delete synced monsters that are no longer usable upstream")
    ap.add_argument("--force", action="store_true", help="HTTP: ignore data/forge_quarantine.json")
    ap.add_argument("-v", "--verbose", action="store_true", help="HTTP: list every file changed")
    a = ap.parse_args()
    forge = a.forge.expanduser()
    if a.registry:
        return write_registry(forge, a.source)
    if a.http:
        return run_http(a)
    if not forge.is_dir():
        print(f"monster-forge not found at {forge}: no monsters synced (the game uses stand-ins).")
        return 0
    for d in (a.dest, a.props_dest):
        d.mkdir(parents=True, exist_ok=True)
        (d / ".gdignore").touch()
    prop_root = forge / "out" / "props"
    all_props = sorted(p.name for p in prop_root.iterdir() if (p / "model.glb").exists()) if prop_root.is_dir() else []
    if a.props is not None:
        return 1 if sync_props(prop_root, a.props or all_props, a.props_dest) else 0

    out = forge / "out" / a.source
    reg = registry(forge, a.source)
    if not out.is_dir():
        print(f"no such directory: {out}", file=sys.stderr)
        return 2
    # --all: every rigged monster that also has clips (a rig without anims/ is still being
    # made, e.g. centaur-trooper in round 4; --ids syncs it anyway).
    ids = a.ids or sorted(p.name for p in out.iterdir()
                          if (p / "model_rigged.glb").exists() and any((p / "anims").glob("*.glb")))
    if a.all:
        for p in sorted(out.iterdir()):
            if (p / "model_rigged.glb").exists() and p.name not in ids:
                print(f"{p.name}: skipped (rigged, no anims/*.glb clips yet)")
    if a.all and a.dest.is_dir():
        for p in sorted(a.dest.iterdir()):
            if (p / "monster.json").exists() and p.name not in ids:
                print(f"{p.name}: kept (no model_rigged.glb upstream right now; delete the folder to drop it)")
    failed = 0
    for mid in ids:
        src = out / mid
        if not (src / "model_rigged.glb").exists() or not (src / "manifest.json").exists():
            print(f"{mid}: skipped (no model_rigged.glb or manifest.json in {src})")
            failed += 1
            continue
        try:
            changes = sync_one(src, a.dest / mid, reg.get(mid, {}), override(forge, a.source, mid))
        except (OSError, ValueError, KeyError) as e:
            print(f"{mid}: FAILED {e}")
            failed += 1
            continue
        print(f"{mid}: " + ("unchanged" if not changes else f"{len(changes)} change(s)"))
        for c in changes:
            print("  " + c)
    if a.all:
        props = all_props
    else:
        props = sorted({w for mid in ids for w in reg.get(mid, {}).get("wields", [])})
    failed += sync_props(prop_root, props, a.props_dest)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
