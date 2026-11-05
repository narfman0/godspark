# Track G: art assets and actor visuals

Branch `ws/assets`. Real art through a fallback chain: a monster-forge GLB when synced, else a
Synty model, else the old tinted primitive (now with a nameplate). Nothing here needs art to
run: with no fetched files every actor is a primitive and dressing is simply absent, headless
or not. The pack survey and the tile metric decision are in
[../assets/survey.md](../assets/survey.md).

## What was built

| File | What |
|---|---|
| `tools/fetch_assets.sh` | Synty fetcher (port of glitchbound's). Default: every literal `res://assets/meshes/...(gltf/glb/png)` under `data/ view/ game/ net/ tools/` plus each glTF's `.bin` and images. `--paths list`, `--list`, `--index` (verify against the server's index.json, write `tests/data/asset_paths.txt`), `--pack` (browsing only). Skips present files, says clearly when the server is unreachable, writes `assets/meshes/.gdignore`, then runs the patcher |
| `tools/patch_gltf_materials.py` | glitchbound's cooked-material fixes (BLEND -> MASK, alpha textures -> MASK, bad texture indices, stray emission). Idempotent |
| `tools/sync_monsters.py` | godot-dnd's monster-forge sync, plus `--registry` (writes `data/looks_creatures.json`), `.gdignore` in the targets, a quiet exit 0 when monster-forge is absent, and a default forge path that works from a worktree |
| `tools/bootstrap.sh` | runs both (`--no-monsters` to skip the sync) |
| `tools/asset_probe.gd` | AABB, bones, clips of glTFs, loaded at runtime |
| `tools/check_looks.gd` | builds every looks row headless, prints body, model, height, clips, load time |
| `data/looks.json` | the looks table: clip sets, 66 Synty model defs, 140 rows (players, peoples, 81 SRD slugs), `by_type`, `by_size`, `default` |
| `data/looks_creatures.json` | generated: size, type, body plan, scale_m, speeds of all 330 SRD monsters (from the forge registry) |
| `data/dressing.json` | 13 meadow and cave decorations |
| `view/actors/gltf_cache.gd` | `GltfCache`: runtime GLTFDocument loading, one generated template per file, duplicated per instance; skinned-mesh AABBs |
| `view/actors/lit_materials.gd` | `LitMaterials`: PBR -> unshaded materials that read the tile light |
| `view/actors/anim_retarget.gd` | `AnimRetarget`: glitchbound's bind-space retargeter, runtime loading, in-place locomotion |
| `view/actors/character_visual.gd` | `CharacterVisual`: a Synty model, fitted, lit, animated |
| `view/actors/forge_monster.gd` | `ForgeMonster`: trimmed port of godot-dnd's `monster.gd` |
| `view/actors/looks.gd` | `Looks`: look -> body plan (pure) |
| `view/actors/actor_body.gd` | `ActorBody`: the actor node (body, nameplate, facing, states) |
| `view/actors/dressing_view.gd` | `DressingView`: MultiMesh decorations from `{id, x, y}` records, plus a deterministic demo scatter |
| `tests/test_looks.gd` | 60 checks: schema, resolution order and fallbacks with faked files, bodies, states, WorldView API, dressing data and scatter, server-index check (offline) |
| `docs/assets/survey.md` | the pack survey, metric decision, cooking problems, modular hero plan |

Edits outside the track's own files (all additive):

- `view/world_view.gd`: `add_actor` builds an `ActorBody` (same signature, still returns a
  Node3D with meta `size`); `move_actor` gained an optional 5th argument `vel := Vector2.INF`
  and passes `state` through; new `get_actor(id)`; `_exit_tree` calls `GltfCache.clear()`.
  The inline capsule code moved into `ActorBody._build_primitive` (same capsule and nose).
- `view/demo.gd`: the walker is `{"player": "fighter"}`, the goblin `{"slug":
  "goblin-warrior"}` (both keep `kind`/`color`, so they are the old capsules when nothing is
  fetched); opts `cave` (a 24-tile tunnel west of the cave pocket for the torch check),
  `noshow`, `nodress`; a showcase cast and meadow/cave dressing.
- `tools/shot.gd`: prints each actor's body kind and the dressing counts.
- `project.godot`: not touched. `K.TILE_M` not changed.
- `.gitignore`: nothing needed (assets/meshes, monsters, props were already ignored).

## API as built

```gdscript
# WorldView (additive)
add_actor(id, look: Dictionary) -> Node3D          # an ActorBody
move_actor(id, pos: Vector2, facing: int, state := "idle", vel := Vector2.INF)
get_actor(id) -> ActorBody

# look keys, all optional
{slug: "goblin-warrior", people: "elf:drow:raider" | "people:elf:drow:raider",
 player: "fighter" | "player:fighter", key: <any row key>, name: "Ash",
 size: Vector2 (tiles), size_name: "small", type: "beast", color: Color, tint, scale,
 height_m, nameplate: bool}
# the original {kind, size: Vector2, color} still works (a primitive named `kind`)

Looks.resolve(look, has_file := Callable()) -> Dictionary
  # {body: forge|synty|primitive, slug, key, model, model_def, forge_dir, size, size_name,
  #  type, plan, name, tint, color, scale, height_m, nameplate}
Looks.keys_for(look) -> PackedStringArray; Looks.table(); Looks.creatures(); Looks.all_paths()

ActorBody.build(look, primitive_mat, has_file := Callable()) -> ActorBody
actor.update(pos, facing, state, vel := Vector2.INF); actor.set_state(s); actor.snap_facing()
ActorBody.state_for(body: Body) -> String       # climb | swim | fly | jump | fall | run | idle
actor.kind, actor.plan, actor.size, actor.visual, actor.turn, actor.nameplate

GltfCache.instance(path) -> Node3D | null; exists(path); state(path); clear()
GltfCache.visible_aabb(node) -> AABB; mesh_xform(mi, stop) -> Transform3D
LitMaterials.apply(root, tint); set_tint(root, tint); lit_for(material); lit_mesh(mesh)
CharacterVisual.setup(def, clips, height_m) -> bool; play(clip, speed); has_clip(c)
ForgeMonster.load_monster(slug) -> ForgeMonster | null; is_synced(slug); play(state, speed)

DressingView.set_objects([{id, x, y}]); DressingView.defs(); counts
DressingView.scatter(world, x0, x1, seed, biome := "meadow", density := 0.45) -> Array
DressingView.placement(def, top_m, x, y) -> Transform3D
```

### Resolution order

1. `look.slug` synced in `assets/monsters/<slug>/monster.json` -> forge.
2. The first row found for the look's keys (slug; `people:a:b:c` then `people:a:b`, then
   `people:a`; `player:<class>` then `player`; `key` likewise), or, with no row, `by_type`
   for the slug's creature type. Its model is used when the model file exists and, for
   humanoids, the reference character and the set's idle clip exist too (no T-poses).
3. Primitive: colour from the look, the row (shaded by its tint), the type, or the default;
   box from `look.size`, else `by_size` for the slug's size (or the row's `size_name`).

Heights: `look.height_m` > row `height_m` > model `height_m` > `by_size` height, times the
row and look `scale`. Synty models are fitted to that height with their feet at the origin.
Forge monsters keep their native metres and only shrink, never grow, to stay within about
1.15x the box height and 2.2x its width.

### States (`move_actor`'s `state`)

| State | Synty humanoid | Forge monster | Primitive |
|---|---|---|---|
| idle / walk / run | by horizontal speed: idle under 0.25 m/s, walk, run, sprint above 5 m/s (scaled by the model's height); playback speed-scaled to the body (clamped 0.6-1.8) | its move clip (walk, else swim / fly / move), speed-scaled | still |
| jump | running-jump clip once, then fall | fly if it has one, else idle | |
| fall | fall-short loop | fly or idle | |
| climb | walk clip, model turned to face the wall, speed from vertical speed | move clip | |
| swim | walk at 0.7 | swim clip | |
| fly | fall clip | fly clip | |
| attack, hit | sword-combat one-shots, fired when the state changes to them, then back to locomotion | attack_melee, hit | |
| death / dead | death clip, held | death, held | lies down |

Facing: the body is yawed to +-(90 - 17) degrees so it faces its travel direction with its
front a little toward the camera; turning takes 0.12 s through the camera-facing side. On a
ladder it turns its back to the camera.

### Light

Every loaded model gets `LitMaterials` shaders: unshaded, albedo texture x colour (x vertex
colour when the glTF asks), times `gs_light_at(world_xy / gs_tile_m)` and the shared face
shading, so models are lit only by LightEngine like the terrain. Alpha-tested foliage keeps
alpha scissor, double-sided materials stay double-sided, skinning is untouched. Textures get
mipmaps generated at load (runtime glTF has none). The dark-cave screenshot shows the skeleton
23 tiles from the torch as a silhouette in black, the bandit 11 tiles away dim, and the dwarf
and goblin next to the torch warm and fully lit.

### Dressing

`data/dressing.json` objects: `model`, `footprint` [w, h] tiles, `anchor` (ground | ceiling),
`fit_h` (height above the model origin in tiles), `z` (plane in tiles: behind the actors for
trees, bushes, rocks; in front for grass and flowers), `depth` (z squash so round trees do not
poke through the terrain front), `jitter`, `where` {biomes, band surface | cave, on: tile
names}, `weight`, optional `tint` and `textures`. One MultiMesh per (object, mesh part);
per-cell hash variation in scale and yaw. Meadow set: Nature `Tree_Generic_01`,
`Tree_Round_02`, `Tree_Large_01`, `Plant_Bush_01`; Meadow rocks, tall and short grass,
wildflowers, sunflower, mushrooms. Caves: EnchantedForest giant mushroom and crystal,
Dungeon_Pack stalagmite.

**Core record format (proposed for worldgen and net):** `{id: u16 (index into a stable
dressing id table, append-only like tiles.json), x: s32, y: s32, v: u8 (variant seed)}`,
anchored at the footprint's bottom-left cell, stored per chunk next to the tile layers and
sent with the chunk. Tiles stay the truth: removing a supporting tile under the footprint or
placing a solid into it removes the record (a harvest event can drop items). The view needs
only the list.

## Fetched, and how big

| What | Files | Size |
|---|---|---|
| Synty (`tools/fetch_assets.sh`, 88 referenced paths) | 179 (glTF, bin, png) | 56 MB (67 MB on disk here, including probe files no longer referenced) |
| monster-forge (`sync_monsters.py --all`, 17 monsters) | | 201 MB |
| monster-forge props (32) | | 18 MB |

Nothing is imported by the editor: the three folders carry `.gdignore` and everything loads
at runtime through GltfCache, so `godot --headless --import` stays at about 1 s.

Measured (headless, this machine): building all 133 looks rows took 4.0 s in total, of which
glTF parsing was 2.8 s for 88 files; a first Synty humanoid of a model costs 20-175 ms
(retargeting 9 clips dominates, cached per model and clip after that); a forge monster
50-170 ms. Screenshots render in about 7 s each under `tools/soft_godot.sh`.

## Tests

`tests/test_looks.gd`: no art needed (file existence is faked), passes with and without the
fetched folders (both checked: `276 checks, ALL PASS`). The server-index check reads
`tests/data/asset_paths.txt`, written by `tools/fetch_assets.sh --index`; adding a model path
without re-running it fails the test with that hint. If the file is absent the check is
skipped with a note.

## Deviations

- Architecture says `add_actor(id, look: {kind, size, color})`: look gained keys, and
  `move_actor` an optional `vel`. Both backwards compatible.
- No editor imports: runtime GLTFDocument for Synty too (glitchbound imported). Exported
  builds will need `assets/*` in the export filter (untested, as in godot-dnd).
- The Meadow pack's trees and bushes are unusable as cooked; the meadow uses POLYGON_Nature
  trees with their atlas restored by data.
- ForgeMonster is trimmed: LOD0 only, no props or sockets, no swarm units.
- `data/looks_creatures.json` is generated from monster-forge's registry and committed (look
  metadata only: size, type, body plan, scale, speeds).
- Old placeholder looks now show their `kind` as a nameplate.

## Known weaknesses

- No climb or swim clips exist in the Synty packs: climbing is the walk cycle facing the wall.
- Run speed (13 tiles/s = 9.75 m/s) is faster than any clip; the sprint clip plays at up to
  1.8x and feet still slide a little.
- Halflings and gnomes are uniformly scaled humans (child-like proportions); kobolds and
  gnolls are tinted goblins and butchers with nameplates.
- SIMPLE animals hold their bind pose (their one baked take was not inspected); quadruped
  forge monsters are animated.
- Static caches (GltfCache templates, LitMaterials, DressingView parts) grow with use and are
  freed only when a WorldView leaves the tree or a tool calls `GltfCache.clear()`.
- Nameplates are unlit Label3Ds (they read in the dark, by design, but also glow).
- Dressing is not culled by distance and is rebuilt whole by `set_objects`.
- The day/cave screenshots were judged by eye; the live demo with real input was not run (no
  display). Attack/hit/death clips were loaded and listed but not looked at on screen.
- Characters' "Dark" Knights texture reads grey; tints are available per row.

## Next steps

1. Building templates as tile stamps with Synty skins: 5-tile bays and 4-tile storeys at
   scale 1.0 (Base kits), castle and dungeon kits at 0.75; back walls and roofs as skins, front
   wall hidden; pieces linked to the tiles they cover.
2. More biomes: Alpine, Arid, Swamp, Jungle dressing rows (sizes probed the same way), and
   check each pack for the cooking problems listed in the survey.
3. Equipment on the modular hero (survey, last section): master UE skeleton, re-skinned parts
   per slot, item -> part table.
4. Dressing records in core (format above), placed by worldgen and replicated with chunks.
5. Port forge LODs and props (hand sockets for weapons), and swarm units.
