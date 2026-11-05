# Track B: light engine and 2.5D rendering

Branch `ws/view`. Everything here runs with no art present.

## What was built

| File | What |
|---|---|
| `core/world/light_engine.gd` | `LightEngine`: per-tile light, sky and block fields, lazy per-chunk computation, exact incremental updates |
| `view/chunk_mesher.gd` | `ChunkMesher`: one chunk's mesh as surface arrays, built on a worker from a main-thread snapshot |
| `view/world_view.gd` | `WorldView`: chunk streaming on `WorkerThreadPool`, light textures, backdrop, placeholder actors, picking |
| `view/camera_rig.gd` | `CameraRig`: 28 degree perspective camera, smoothed follow, zoom |
| `view/shaders/` | `light.gdshaderinc` (shared light lookup), `terrain`, `backdrop`, `actor` shaders |
| `view/demo.tscn`, `view/demo.gd` | fly over `TileWorld.make_test()`: WASD/arrows, wheel zoom, LMB dig, RMB place stone, T time of day, L toggle the walker's torch |
| `tools/shot.gd` | renders the demo to a PNG under `tools/soft_godot.sh`, prints timings and a picking check |
| `tools/bench_view.gd` | headless timings for meshing and light |
| `tests/test_light.gd`, `test_chunk_mesher.gd`, `test_world_view.gd` | 49 checks between them |

`project.godot` gained a `[shader_globals]` section (the six `gs_*` globals below). That is
the only change outside the track's files.

## Light model

- Levels are bytes. Spreading is a Dijkstra flood on a bucket queue over 8 neighbours:
  orthogonal step `STEP = 5`, diagonal `DIAG = 7` (ratio 1.4, so distances are close to
  Euclidean). A diagonal step needs both cells it squeezes between to be clear.
- `TORCH = SUN = 85 = DIM_MIN + 16 * STEP`, `BRIGHT_MIN = 45`, `DIM_MIN = 5`, `MAX = 125`.
  A torch reads BRIGHT to 8 tiles (20 ft) and DIM to 16 tiles (40 ft) along axes and
  diagonals (tested at (5,5) bright, (6,6) and (11,11) dim, (12,12) dark).
  `strength_for_ft(total_ft)` gives the strength for "bright for half, dim for the rest"
  lights (lantern 60 ft gives 125 = MAX). Note: with fixed thresholds, only a torch-strength
  light gets exactly bright = half; a lantern reads bright to 16 tiles, not 12.
- Two fields: `sky` (sunlight) and `block` (emissive tiles, carried lights).
  `level = max(block, round(sky * sun))`, so changing `sun` recomputes nothing.
- Sun: a cell is direct sun (`SUN`) when it is not opaque and nothing opaque is above it
  in its column (`sky_top(x)`, scanned lazily per column). Background walls do not change
  light at all: a covered cell gets only what spreads to it, with or without a wall.
- Opaque tiles receive light (so cave-wall faces are lit), and pass it only to other opaque
  tiles, orthogonally, at `SOLID_STEP = 22` per tile, never back into open cells. Air-cell
  levels are therefore exactly what they would be if rock blocked light completely (tested
  with a sealed pocket next to a torch). The view uses this to show 2-3 tiles of rock under
  a lit surface instead of a black line one tile down.
- Emissive tiles are treated as non-opaque for light.
- Laziness: chunks are computed in batches of up to 4x4 chunks, padded by the reach of the
  strongest source (`ceil(strongest / STEP)`, 17 tiles now), so a computed chunk is exact.
  `level_at` computes on demand.
- Edits: a change can only affect cells within `reach` of it. `_update(box)` refloods `box`
  seeded from the stored values in a one-cell frame around it (the frame is outside the
  change's reach, so it is exact). For a sun-column change the box is the column span between
  the edit and the next opaque tile below, grown by `reach`. Tests compare the whole world
  after a series of digs, placements, torch removal and carried-light moves against a fresh
  engine: identical, both fields.
- Memory: two bytes per tile for the whole world, allocated up front (8400x2400 would be
  40 MB).

## API as built

```gdscript
LightEngine.new(world: TileWorld)
light.level_at(x, y) -> int                    # 0..MAX, computes the chunk if needed
light.category_at(x, y) -> LightEngine.Category  # DARK, DIM, BRIGHT
LightEngine.category_of(level) -> Category
light.sun = 1.0                                # clamped 0..1; emits light_changed(whole world)
light.add_light(id, x: float, y: float, strength: int)   # adding an existing id moves it
light.move_light(id, x, y); light.remove_light(id); light.has_light(id)
light.ensure_region(rect: Rect2i)
light.is_computed(cx, cy) -> bool
light.reset()                                  # forget everything
signal light_changed(rect: Rect2i)
# extras for the view and for rules:
light.block_at(x, y), light.sky_at(x, y)       # raw fields (sky not scaled by sun)
light.region_bytes(rect, sky: bool) -> PackedByteArray   # R8 rows bottom-up; no computing
light.sky_top(x) -> int
LightEngine.emit_level(emit: int) -> int       # tiles.json emit 0-15 -> level (15 = TORCH)
LightEngine.strength_for_ft(total_ft) -> int
const STEP, DIAG, SOLID_STEP, MAX, DIM_MIN, BRIGHT_MIN, TORCH, SUN

ChunkMesher.snapshot(world, cx, cy) -> Dictionary   # main thread, ~10 us, copies 9 fg arrays + bg
ChunkMesher.build_arrays(snap) -> Array             # any thread; Mesh.ARRAY_MAX surface arrays or []
ChunkMesher.to_mesh(arrays) -> ArrayMesh            # main thread
ChunkMesher.build(world, cx, cy) -> Array           # snapshot + build_arrays
const FRONT = 0.5, BACK = -0.5, BEVEL = 0.2, WALL_Z = -0.5   # tile units in z

WorldView (Node3D)
  setup(world, light)
  set_focus(pos: Vector2)                      # tile units
  view_half: Vector2                           # half the area to keep, tiles (from CameraRig)
  add_actor(id, look: {kind, size: Vector2, color}) -> Node3D
  move_actor(id, pos: Vector2, facing: int, state := "idle")   # "dead" lays it down
  remove_actor(id)
  tile_at_screen(screen_pos: Vector2) -> Vector2i   # ray onto the front plane
  is_idle() -> bool; chunk_count() -> int; stats: Dictionary of timings (usec)
  WorldView.sky_color(sun), WorldView.horizon_color(sun)

CameraRig (Node3D)
  target: Vector2, pos: Vector2 (smoothed), zoom (0.3..4), fov = 28, tiles_tall = 36
  snap(); visible_half_extent() -> Vector2; distance() -> float; camera: Camera3D
```

### Mesh layout

Tile (x, y) occupies `[x, x+1] x [y, y+1] * TILE_M`; blocks span z from `BACK` to `FRONT`
(one tile deep, centred on the actor plane z = 0). Front faces are greedy rectangles (runs of
one id with the same top/bottom exposure, stacked when their spans match). Every edge facing
a non-solid cell gets a 45 degree bevel and a side face back to `BACK`; runs along an edge
are merged; bevels mitre at outer corners and get two filler triangles at inner corners. Open
cells with a wall get a merged wall plane at `WALL_Z`. Non-solid tiles are posts (a torch is
a stick with an emissive head). Top of the world reads as air, other outside cells as bedrock.

Vertex data: `COLOR` = tile colour (linear), `UV2 = (tile or wall id, kind)` with kind 0
block, 1 emissive, 2 wall, `UV` = world tile coordinates on the face's plane. A texture array
can replace the colours by sampling layer `UV2.x` at `UV`; nothing else changes. Per-tile
colour variation, a faint grain and grout lines between front tiles come from hashes in the
shader, so they do not stop merging.

### Light on screen

`WorldView` keeps two R8 `ImageTexture`s (block and sky, raw levels, one texel per tile)
over a rectangle around the focus (visible area + 24 tiles, snapped to 8; it recentres when
the view nears its edge) and refills them on `light_changed` that touches the rectangle.
Global shader uniforms (in `project.godot`): `gs_light_block`, `gs_light_sky` (filter_linear,
so falloff is bilinear), `gs_light_rect` (origin, size in tiles), `gs_sun`, `gs_sky_tint`,
`gs_tile_m`. Any material can `#include "res://view/shaders/light.gdshaderinc"` and call
`gs_light_at(world_xy / gs_tile_m)`; the actor shader does exactly that. All shaders are
unshaded: the only light is LightEngine's, so an unlit cave is black (ambient 0.004).
Block light is tinted warm, sky light by `gs_sky_tint` (warmer at dusk). The backdrop is a
world-sized quad 1.2 m behind the walls: a sky gradient where the sky field reaches, dark
rock lit faintly by block light where it does not (caves with no background wall).

## Deviations from architecture.md

- `ChunkMesher.build(world, cx, cy)` returns surface arrays (`Array`), not a mesh, and is
  split into `snapshot` (main thread) / `build_arrays` (worker) / `to_mesh` (main thread).
  Reading the live world from a worker would race with edits; the snapshot duplicates the
  arrays (packed arrays are shared by reference in Godot 4, a test covers it).
- `add_light` with an existing id moves it (and can change strength) instead of failing.
- Additions listed in the API above (`region_bytes`, raw field getters, constants,
  `WorldView.tile_at_screen`, `view_half`, `CameraRig`). `architecture.md` itself was not
  edited; the Track B block there is still accurate for what it lists, apart from `build`'s
  return type.
- The brief says emissive tiles and carried lights "add to" sunlight; they combine by max
  (two torches do not make a bigger bright radius, matching SRD).

## Measured (this machine, `godot --headless -s res://tools/bench_view.gd`)

512x256 test world with random caves, single thread, GDScript:

| What | Time |
|---|---|
| chunk mesh build, 32x32 | avg 0.86 ms, median 0.75, p95 1.54, max 1.78 (833 verts avg) |
| of which: padded 34x34 id grid fill (an all-air chunk costs this) | ~0.47 ms |
| snapshot (main thread) | 0.005 ms |
| ArrayMesh upload (main thread, from shot runs) | ~0.05 ms |
| light, one chunk from cold (66x66 flood incl. padding) | 8.0 ms |
| light, 160x112 tiles (the light texture area) from cold | 32 ms |
| light, rest of the 512x256 world | 191 ms |
| dig one buried tile (incremental) | 1.0 ms |
| dig one surface tile (sun column changes) | 1.65 ms |
| carried torch moves one tile | 0.85 ms |
| light texture bytes, both fields 160x112 | 0.05 ms |

Mesh time is dominated by GDScript per-vertex appends in the edge pass and the grid fill;
under the 4 ms target with room. Light from cold dominates main-thread cost (below).

## Known weaknesses

- **Light from cold runs on the main thread.** First view of an area costs ~8 ms per new
  chunk (32 ms for the whole start-up texture area). Scrolling into new chunks will hitch.
  Fix: run `ensure_region` for the next ring of chunks on a worker (LightEngine is not
  thread-safe yet: it would need to flood into a private buffer and commit on the main
  thread), or cap batches per frame.
- Light textures are refilled whole on any change inside them (cheap now: 0.05 ms plus the
  upload of two ~20 KB textures).
- The shot tool only proves single frames; the live demo (input, dig/place, time cycle,
  walker with a carried torch) was not exercised interactively here: no real display.
  Picking was checked (screen centre maps to the camera's tile).
- Side faces show only toward the screen edges at 28 degrees; depth reads mostly from bevels.
- Colours are flat per tile id with hash variation; no textures, no liquids drawn, no
  parallax layers (optional, not done), no real `OmniLight3D`s for torches.
- `chunk_changed` refloods the sun field for the whole column span below the chunk: fine for
  a chunk arriving from the host, slow if many arrive at once on a tall world.
- Light memory is world-sized up front.
- Not tried with Track A's `WorldGen` (it did not exist on this branch). `demo.gd` looks the
  class up by name when given `gen=seed`, so it has no compile-time dependency.

## Next steps

1. Move cold light computation off the main thread (worker flood into a scratch buffer,
   commit on main).
2. Texture array for terrain from Synty palette textures, keyed by `UV2.x`.
3. Real `OmniLight3D`s for the few nearest torches and spells, for specular and actor rim.
4. Parallax backdrop layers (hills, cave rock), liquids, tile-anchored dressing objects.
5. Actors through the looks table (Track G), with `light.gdshaderinc` in their materials.
