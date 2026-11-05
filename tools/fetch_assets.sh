#!/usr/bin/env bash
# Fetch cooked Synty meshes and textures from the asset server into assets/meshes/.
# The server is the source of truth; fetched files are git-ignored and never committed.
#
#   tools/fetch_assets.sh                    # DEFAULT: only what the project references
#                                            #   (+ each glTF's .bin and textures)
#   tools/fetch_assets.sh --paths list.txt   # explicit server paths (assets/<Pack>/...), one per line
#   tools/fetch_assets.sh --list             # print the referenced paths, fetch nothing
#   tools/fetch_assets.sh --index            # check the referenced paths against the server's
#                                            #   index.json and write tests/data/asset_paths.txt
#                                            #   (tests/test_looks.gd reads it, offline)
#   tools/fetch_assets.sh --pack Nature …    # whole packs (big: browsing only, never for the game)
#
# "Referenced" means a literal res://assets/meshes/<Pack>/....(gltf|glb|png) anywhere in
# data/**/*.json, view/, game/, net/, tools/ (*.gd, *.tscn, *.tres, *.json). data/looks.json
# and data/dressing.json hold every model and animation clip the game uses, so they are
# what drives this. Nothing loads meshes by directory scan.
#
# Idempotent: files already present are skipped. assets/meshes/.gdignore is written so the
# Godot editor never imports the fetched tree (the game loads it at runtime with
# GLTFDocument). Afterwards tools/patch_gltf_materials.py fixes cooked material problems.
# Env: ASSET_SERVER (default http://srv.blastedstudios.com:49200).
set -euo pipefail
cd "$(dirname "$0")/.."

SERVER="${ASSET_SERVER:-http://srv.blastedstudios.com:49200}"
DEST="assets/meshes"
MODE="used"
ARGS=()
case "${1:-}" in
	--pack) MODE="pack"; shift; ARGS=("$@") ;;
	--paths) MODE="paths"; shift; ARGS=("$@") ;;
	--list) MODE="list"; shift ;;
	--index) MODE="index"; shift ;;
	"") ;;
	*) echo "unknown option: $1 (see the header of $0)" >&2; exit 2 ;;
esac

mkdir -p "$DEST"
[[ -f "$DEST/.gdignore" ]] || : > "$DEST/.gdignore"

SERVER="$SERVER" DEST="$DEST" MODE="$MODE" python3 -I - "${ARGS[@]}" <<'PYEOF'
import json, os, re, glob, sys, urllib.request, urllib.parse, urllib.error

SERVER, DEST, MODE = os.environ["SERVER"], os.environ["DEST"], os.environ["MODE"]
LOCAL_PREFIX = DEST + "/"        # local:  assets/meshes/<Pack>/...
SERVER_PREFIX = "assets/"        # server: assets/<Pack>/...

def to_server(fs): return SERVER_PREFIX + fs[len(LOCAL_PREFIX):]
def to_local(sp): return LOCAL_PREFIX + sp[len(SERVER_PREFIX):]

def referenced():
    out = set()
    pat = re.compile(r'res://(assets/meshes/[^"\'\n]+?\.(?:gltf|glb|png))')   # paths may hold spaces
    for base in ("data", "view", "game", "net", "tools"):
        for f in glob.glob(base + "/**/*", recursive=True):
            if os.path.isfile(f) and f.endswith((".gd", ".tscn", ".tres", ".json")):
                out.update(m for m in pat.findall(open(f, encoding="utf-8", errors="ignore").read())
                           if "..." not in m and "<" not in m)   # skip examples in doc comments
    return sorted(out)

if MODE == "list":
    for r in referenced():
        print(r)
    sys.exit(0)

def reachable():
    try:
        req = urllib.request.Request(f"{SERVER}/index.json", method="HEAD")   # / redirects to https
        urllib.request.urlopen(req, timeout=8).close()
        return True
    except urllib.error.HTTPError:
        return True          # the server answered, even if / is not a page
    except Exception as e:
        print(f"Asset server {SERVER} is unreachable ({e}).", file=sys.stderr)
        print("Nothing fetched. The game still runs: every model falls back to a primitive.", file=sys.stderr)
        return False

def http_get(server_path, out_fs):
    os.makedirs(os.path.dirname(out_fs), exist_ok=True)
    url = f"{SERVER}/{urllib.parse.quote(server_path)}"
    with urllib.request.urlopen(url, timeout=60) as r:
        data = r.read()
    tmp = out_fs + ".part"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, out_fs)
    return len(data)

closure, seen, missing = set(), set(), []
fetched = [0, 0]
server_ok = None

def ensure(fs):
    """Fetch a file if absent; for .gltf, recurse into its buffers and images."""
    global server_ok
    fs = os.path.normpath(fs)
    if fs in seen:
        return
    seen.add(fs)
    closure.add(fs)
    if not os.path.isfile(fs):
        if server_ok is None:
            server_ok = reachable()
        if not server_ok:
            missing.append(fs)
            return
        try:
            n = http_get(to_server(fs), fs)
            fetched[0] += 1
            fetched[1] += n
            print(f"  fetched {fs[len(LOCAL_PREFIX):]}")
        except Exception as e:
            missing.append(fs)
            print(f"  MISS {fs[len(LOCAL_PREFIX):]}  ({e})", file=sys.stderr)
            return
    if fs.endswith(".gltf"):
        try:
            d = json.load(open(fs))
        except Exception:
            return
        base = os.path.dirname(fs)
        for section in ("buffers", "images"):
            for item in d.get(section, []):
                uri = item.get("uri")
                if uri and not uri.startswith("data:"):
                    ensure(os.path.join(base, urllib.parse.unquote(uri)))

if MODE == "index":
    if not reachable():
        sys.exit(1)
    index = json.load(urllib.request.urlopen(f"{SERVER}/index.json", timeout=120))
    on_server = {f["path"] for p in index["cooked"]["packs"] for f in p["files"]}
    refs = referenced()
    bad = [r for r in refs if to_server(r) not in on_server]
    for r in bad:
        print(f"  NOT ON SERVER {r}", file=sys.stderr)
    good = [r for r in refs if r not in bad]
    os.makedirs("tests/data", exist_ok=True)
    with open("tests/data/asset_paths.txt", "w") as fh:
        fh.write("# Referenced asset paths verified against the asset server's index.json.\n")
        fh.write("# Written by tools/fetch_assets.sh --index; read by tests/test_looks.gd (offline).\n")
        for r in good:
            fh.write(r + "\n")
    print(f"{len(good)} referenced paths on the server, {len(bad)} not: tests/data/asset_paths.txt")
    sys.exit(1 if bad else 0)

if MODE == "pack":
    print("WARNING: whole packs are large (thousands of files). Use only for browsing.", file=sys.stderr)
    if not reachable():
        sys.exit(1)
    index = json.load(urllib.request.urlopen(f"{SERVER}/index.json", timeout=120))
    for want in sys.argv[1:]:
        for p in index["cooked"]["packs"]:
            if want.lower() in p["name"].lower():
                print("==", p["name"])
                for f in p["files"]:
                    if f["path"].endswith((".gltf", ".glb", ".bin", ".png")):
                        ensure(to_local(f["path"]))
elif MODE == "paths":
    for listfile in sys.argv[1:]:
        for line in open(listfile):
            line = line.strip()
            if line and not line.startswith("#"):
                ensure(to_local(line) if line.startswith(SERVER_PREFIX) else line)
else:
    refs = referenced()
    for r in refs:
        ensure(r)
    print(f"Referenced: {len(refs)} assets.")

have = [p for p in closure if os.path.isfile(p)]
size = sum(os.path.getsize(p) for p in have)
print(f"Closure: {len(have)}/{len(closure)} files present, {size/1048576:.1f} MB "
      f"(fetched now: {fetched[0]} files, {fetched[1]/1048576:.1f} MB).")
if missing:
    print(f"{len(missing)} file(s) missing.", file=sys.stderr)
    sys.exit(1)
PYEOF

python3 -I tools/patch_gltf_materials.py
