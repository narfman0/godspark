# Track: the look below (M6 track 5, deliverable 6)

Branch `ws/look-below`, cut from main 2fc1fc3. View-only apart from one small host call, listed under
Deviations. Worlds do not move: `tools/world_hash.gd` gives the same content hash with and without this
track's `data/dressing.json` on dev seeds 3 and 4 and medium seed 1.

**Every picture is with no art.** Nothing is fetched on this machine (not here, not in the main
checkout), so the forest, the shards and the city's pieces below are all primitives. See Open.

## What to look at first

Walk into a fungal region (medium seed 1, x 639-1403, about y 951): a forest of mushrooms up to 16 tiles
tall with teal and violet gills, and they light you. Then the crystal (x 6887-7460, y 943), the lake
(x 2448-3059, water near y 400), the lava tubes (x 2103-3378, y 47), and a drow city
(`gen=dev seed=4`). With a torch in the plain underdark, the torch is still the only light.

| Asked | Done | Look at |
|---|---|---|
| Dressing per underground region | Yes, 30 rows (and 5 drow), drawn from the tiles | Any region |
| The fungal picture reads as a forest | Yes | `region=fungal` |
| Each biome by its own light | Yes: teal/violet, blue, green, red | All four side by side |
| The lake's light | Yes, the water has a faint light of its own | `region=deep_lake` |
| Fog of the deep | Yes, by region, black in the plain underdark | Same |
| View hides what combat marks Invisible | Yes, including a client arriving late | `tour=below` shots 45, 45b, 46 |
| Drow architecture | Partly: spires, webs, globes, banners; the buildings' block shape is unchanged | `tour=deep` shots 33, 34 |
| Primitive fallbacks | Yes, for all of the above and the drow kit | This whole report |

## What was built

### Region dressing (`view/actors/region_dressing.gd`, `data/dressing.json`)

The handoff said `where.biomes` can name regions now. For caves it cannot: `stage_dressing._caves` passes
`""` as the biome, so the list is skipped, and it samples one point per 700 tiles at 35%, far too thin for a
forest. Worldgen is off limits to this track, so the scatter is on the view side.

- `RegionDressing` hashes over a chunk's floors and ceilings and picks from rows with `where.band`
  `"below"`. Same tiles, same objects on every client. No record, no network, no seed moved. A dug floor
  loses its mushroom (cache follows `tile_changed` and `chunk_changed`).
- `where.biomes` names regions (`BiomeIds.region_at`), `where.on` the tiles, `gap` spaces large rows,
  `where.chance` replaces the region's density, `where.back` and `where.not_back` name the walls a row
  may stand before. Table `below` in the file: `density`, `ceiling`, `field_lights`.
- Rows are in `ids` so core can own them later. They are inert in worldgen: `stage_dressing` files band
  `below` with the surface rows, and their `where.biomes` name no surface biome, so no candidate is added
  and no RNG is used.

Rows: fungal 9, crystal 6, lake 6, magma 6, underdark 3, and 5 drow rows that name no region: 35 in all.

### Primitives (`view/actors/prim_mesh.gd`, `view/shaders/prim.gdshader`)

A row's `prim` is a list of lathes and boxes in JSON, so a new prop needs no code. Vertex alpha is glow,
so gills and crystal tips read where nothing lights them. `DressingView.parts_of` falls back to `prim` when
a row has no model or its file is missing. All 35 below rows are prim only. Also given a `prim`:
`cave_mushroom`, `crystal`, `stalagmite` and every piece the drow kit reaches. Surface towns with no art get
the shared furniture too, a side effect; their trees still draw nothing.

### Light, fog, lake, lava (`view/below_look.gd`, `view/shaders/deep_fog.gdshader`, `terrain.gdshader`)

- **Colour.** The field has no colour, so all block light was torchlight. `gs_below_tint`, a map at one texel
  per 4 tiles, colours it by what lights it. Tile rows in `data/looks.json` `lights` carry `color` and
  `tint`. With no tinted source in the rectangle the map is clear, so the surface and torch-lit caves are as
  they were. The carried light keeps its own colour near the hand (`gs_own_lamp`).
- **Fog.** `gs_below_fog` holds each region's colour and density (`data/backdrops.json` `below`). A sheet
  just in front of the walls draws banks and motes, stronger where the field is lit.
- **Glowing props.** A row's `light` makes it a source in the view's own `LightEngine`, nearest
  `field_lights` (14), two changes a frame, plus a lamp and a tint. The presenter's engine is not the host's.
- **Lake.** Water inside `meta.descent.lake` gives a faint light, brightest along the surface, with sparks.
- **Lava.** A flowing noise instead of a grid of tiles.
- **Soft rock.** The regions' tiles and walls were missing from `ChunkMesher`'s natural lists, so they were
  drawn as grouted blocks.

### Invisible (`view/actors/unseen_rule.gd`, `game/view_presenter.gd`)

CONDITION events drive `UnseenRule`: a creature is gone (body, shadow, plate, target ring). Yourself and
other players stay faint, as does what `see-invisibility` or `true-seeing` shows. That rule is mine: the host's
`can_see` models neither spell, so those two ids are unverified against a real cast.

Live: `tour=below` prints `by the torch the roper's body is gone`, in a cave the torch has lit.

### Drow (`data/dressing.json`, `terrain.gdshader`)

`dark_stone` is used only by the drow style, so rows `on` it are drow rows in any region, and
`data/places/kits.json` is unchanged. Spires and finials on roofs (`not_back: dark_wall`); globes, banners and
idols in rooms (`back: dark_wall`). Drow masonry and `dark_wall` carry a spider's web in fae light, a shader
pattern by tile id. Primitives for each kit piece.

## API as built

- `RegionDressing.new(world)`, `.records_in(cx, cy)` -> `[{id, x, y}]`, `.covers(y)`, `.meta_changed()`;
  static `rows()`, `matches(def, biome, under)`, `backed(def, wall)`, `candidates(...)`, `density(biome)`,
  `chance(def, biome, ceiling)`, `on_gap(x, gap)`.
- `PrimMesh.build(prim)` -> `{parts, top}` or `{}`.
- `BelowLook` (`WorldView.below`): `row(biome)`, `tile_light(name)`, `tint_bytes`, `fog_bytes`, `set_props`,
  `lit_props`, `props_settled`, `rect_changed`, `emitters_changed`, `meta_changed`.
- `UnseenRule.show(invisible, own, player, sees)`, `.sees_invisible(effects)`; `ActorBody.set_shown(s)`;
  `FxView.unseen`.
- `CombatSystem.tell_unseen(e, to)`.
- Globals in `project.godot`: `gs_below_tint`, `gs_below_fog`, `gs_own_lamp`, `gs_lake`, `gs_lake_glow`.
- Data: `dressing.json` `below`, row `prim` and `light`, `where.chance/back/not_back`; `backdrops.json` `below`;
  `looks.json` `lights` tile rows with `tint`.
- Tools: `look_shot.gd region=NAME [at=0.5]`, `tools/below_bench.gd`, `tools/world_hash.gd`. `tour=below` gains
  shot `45b` and a printed verdict.

## Deviations

- **Outside the view:** `CombatSystem.tell_unseen` and a call from `HostEndpoint._snapshot`. CONDITION events go
  only to clients watching when it changes, so one walking up to a lurker hidden earlier would see it. It uses
  the existing per-peer SYS, no protocol change. It is not the worldgen, sim or Life the track was barred from,
  but it is not view code, and `core/combat` and `net/` were not listed as mine.
- `tests/test_looks.gd` now allows prim-only rows and band `below`.
- `ActorBody._surfaces()` now drops freed nodes. Its `is_instance_valid` ran after a typed assign, so it could
  never help; an early call of mine exposed it (920 SCRIPT ERRORs in a tour, 0 now).
- Glowing props light the picture, not the rules. A player can stand visibly lit by a mushroom in the rules' DARK.
- `architecture.md` is not updated, to keep clear of the integration track's M6 contracts: copy "API as built".

## Measured

| What | Number |
|---|---|
| Cold scan, 49 chunks (fungal / crystal / underdark) | 110.9 / 135.8 / 96.1 ms, worst chunk 6.2-7.4 ms |
| Warm | 0.02-0.04 ms |
| Records, lights in those chunks (fungal) | 796, 287 |
| Fog map, tint map | 1.3-3.7 ms, 0.01-2.2 ms, on a rectangle move or new emitters |
| Frame, fungal, CPU renderer, 1280x720 | 49.3 ms with dressing, 40.9 ms without; draws 52 vs 41, prims 75468 vs 31645 |

GPU frame time is not measured. The cold scan runs inside `_dress`, so entering the deeps costs about 100 ms
once and a new row of chunks about 15 ms, on top of `set_objects` rebuilding everything as it always has.

## Pictures

All rendered and looked at (`tools/soft_godot.sh`, 1280x720, no art). None committed.

- **Fungal.** Before: a grey floor with small cyan caps. After: reads at once as a forest, the best of the set.
  Faults: a very faint vertical seam in the fog near the middle of the frame, cause not found; the floor's colour
  changes abruptly from teal to violet under a mushroom, the tint map's coarseness.
- **Crystal.** Strong at `at=0.75`: clusters of shards light their chamber. At `at=0.25` half the frame is black and
  a stair of dark rock crosses it. It depends where you stand: chambers without shards are simply dark.
- **Lake.** The shore by moss and reeds reads well. The water is dark teal with sparks and a bright surface line.
  The line is ruler straight and a little neon. The air over the water is very large and very dim.
- **Magma.** Good: brown haze, black spires with ember tips, a lava pool that flows. Its rim is still a hard rectangle.
- **Underdark.** Black with no light, on purpose (the PNG is empty but for the name). By torch it is unchanged.
- **Drow street.** Violet light, spires, webs on the walls, hung banners: it reads as a drow city, not a dyed town.
  Still flat roofs with block crenels, the street lamps are the plain stick, and wooden furniture is shared with
  surface towns. Moderate, not finished.
- **Roper.** `45b`: the torch lights the cave, nothing stands there. `46`: it appears when it springs, behind the
  large red swing cone (the fix round's item).
- **Aboleth lair (`47`).** The tour digs a pool in plain rock on dev 4, outside `meta.descent.lake`, so it shows
  ordinary water with no glow. It says nothing about the lake.

## Gate

`tools/gate.sh` on 4fa1c78 (clean): import 0; all eight smokes PASS; `test_m4_e2e,test_m5_e2e` unseeded three times,
210 checks ALL PASS each. **The suite failed: 10517 checks, 1 file:** `test_sim_world`, "strategic day under 4 ms"
at 4.52 ms. That is not this branch: an export of base 2fc1fc3 fails the same check alone (4.28, 4.14, 4.49 ms against
4.26, 4.46, 4.47 here). It failed in every run on this machine today and passed at the handoff, so main is not green on
it here. I left it alone: it is a sim test. After the gate, two small cleanups (a line in `tint_bytes`, `_invisible` cleared with the view): the suite again, 10517 checks, the same single failure at 4.45 ms, and `tour=below` with 0 SCRIPT ERRORs. The smokes and end-to-end runs were not repeated on that last commit.

`tests/test_look_below.gd`: 96 checks, ALL PASS.

## Open

- **Not seen with art.** Rows with a model take the old path, unchanged, but no picture of a fetched model exists from
  this track. The asset server answered 200; I did not fetch. The below rows have no models, so the forest
  looks the same either way, beside surface art it was not compared with.
- `test_sim_world`'s 4 ms threshold, above, for whoever owns it.
- `see-invisibility` and `true-seeing` as effect ids are unverified, and combat does not honour them.
- Region dressing needs `meta.biomes` regions: a world under 2048 wide or an old save has none, drow rows included.
- A drow row depends on `dark_stone` staying drow-only. A player placing the tile would grow spires.
- The fog's seam and the coarse tint edges, above. Drifting motes can still read as stars in a tall dark cavern.
- Only one lake is supported (`gs_lake`), as `meta.descent.lake` is one record.
- Lake water away from any light is never seen against rock, only as the line and the sparks; judge it by playing.
- Stale comment in `world_tour.gd`: "no generated world has a deep lake until the deep biomes land".
- Sound below is still later, as `m6.md` says.
- One render of five exited without a picture in a parallel batch and did not recur; cause unknown.
