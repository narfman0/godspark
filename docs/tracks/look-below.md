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

## Polish pass (view only)

A visual pass after the track, on the same branch: corner and edge artifacts on real generated terrain,
and the six faults listed in the brief. View, shaders, `data/backdrops.json`, `data/lighting.json` and tools
only. No worldgen, sim, Life or sim test is touched. `core/world/light_engine.gd` is unchanged: no fault
turned out to be caused there.

Pictures: `tools/look_shot.gd gen=medium seed=1` from a cached world, at the five regions, a plain torch-lit
cave, a dug shaft to the sky, three cave mouths (day and night), a sinkhole, mountain, forest, desert and
swamp by day, the spawn town by day, dusk and night, both drow towns of medium seed 1, plus zooms 2 and 4;
`tools/place_shot.gd style=drow seed=4`; `tools/corner_shot.gd` in every new mode. Each before (an export of
92b1370) and after, looked at whole and in crops. None committed.

### What was wrong, and why

- **Rock was a void with a glowing rim (faults 1, 2, 3, 4).** One cause under all four. The field holds
  nothing inside rock, so a rock face (the cut-away, seen in section) read its own tile's black, with a
  half-tile rim of bilinear spill from the open cell beside it. That rim follows the tile grid: every
  diagonal cave edge was a stair of steps, every lit pocket a stepped halo (4), a three-tile ledge lit from
  above and below had a black streak through it with a hard lower edge where the underside bevel, which
  reads the open cell below, began (1), and every cavern sat in black (2, 3).
- **Coarse blocks on walls (1, 4).** Two causes. Walls read the field bilinearly at a texel a tile, whose
  creases show as squares in dim light. The brown blocks in the crystal cavern are `cobble_wall` (the deep
  road's tunnel, built), and built walls were a flat colour hashed per tile.
- **A stair where rock meets water or lava** (the lake's slope, a pool's rim): a cut corner beside a liquid
  left its wedge empty, and an inner corner got its fillet only when the cell was air.
- **Dark shapes under towns.** The ground's sun share read the sky field 9 and 20 rows up, so every house
  and tree cast a blurred dark silhouette twenty rows into the earth (desert, meadow town, the forest cave
  under a village). `meta.surface` could not replace it as it was: it is the top of the built world, roofs
  included.
- **Rock blurred at zoom 1 (4).** Natural ground had no detail finer than about forty tiles.
- **The fog seam (6)** was not in the fog: it stays with the fog sheet off, and with shadows off. It was
  the far term of the new rock glow at first (a bilinear crease of a 16-tile mip texel sharpened by a
  smoothstep), found by bisecting; the old seam in the report is likely the same kind of crease of the
  fog's own bilinear read of the field, which no longer shows either.
- **Teeth along shadow edges.** At zoom 4 under a sinkhole's deck a row of small teeth runs along each
  shadow edge: the sun's hard shadow map. Gone with `shadows=high` and `off`.
- **The lake (3):** its line was a flat glow term `0.8 * exp(-d * 1.6)` on a dead-straight sheet.
- **Drow street (5):** merlons are cube teeth, `fae_lamp` the plain stick every lamp is.

Not bugs:

- `corner_shot` rooms of every region's rock, by torch and by day: no black or white notches on the bump,
  the hole, the notches, the pillar or the steps. The same holds on real terrain at the corners looked at:
  the corner work on main holds.
- The black column at the left of the crystal shot is a nine-wide pillar of crystal stone far from light: a
  rock mass, now dark blue instead of black.
- The flat posterised bands in my first contact sheet of the corner rooms were ImageMagick reducing a
  six-picture montage to a palette. The renders are smooth.
- The plain underdark by torch: dark is dark there, still.

### What changed

| Commit | What |
|---|---|
| 67a5584 | A cut corner beside water or lava holds that liquid's sheet; water, lava and a light in a cell take the fillet like air. Slopes into the lake and pools are slopes. |
| f9ed25e | **Rock faces show the light beside them.** The light fields get mipmaps; a new solid map (`gs_solid`, a byte per tile from `ChunkMesher.opaque_bytes`, wrapping like the material map, mipmapped) is read at the same levels; a front face of solid ground shows the mean light of the open cells near it (levels 1 and 3 summed, divided by their open share), fading a tile or two into the rock (`gs_face_levels`). The light rectangle's origin is on a 16-tile grid so the levels line up with the world and do not crawl. Walls read the field through a cubic B-spline (`gs_levels_smooth`). Deep regions' rock and walls near their light take a faint glow of the region's colour (`backdrops.json` `rock`, `rock_glow`; `BelowLook.rock_bytes`, `gs_below_rock`); none in the plain underdark. |
| 6e0eaf0 | The ground's sun share fades with depth under the ground line (`gs_surface`): `meta.surface`, else the client's `sky_line`, stepped down past built tiles, air and water to natural ground (`WorldView.ground_under`). A world with neither keeps the old read. |
| 7dc3310 | Natural ground and walls get a mottled grain, sparse fine cracks (front faces) and a little relief from the grain's slope against the key light (screen derivatives). |
| b41a5af | Water's whole-row edges ride a slow swell (vertex shader; every vertex on a row by the same function of x, so the sheet stays joined). The lake's line is a soft band broken into glints. Rock within a few tiles of the lake takes a faint glow of the water's colour. |
| 95986c3 | `shadows.low.sun_soft`: the sun alone at Godot's very low soft filter; lamps stay hard. |
| 980798f | `tests/test_look_polish.gd`. |
| 6066760 | Cut-away faces take 0.35 of the real lights (sun and lamps): such a face is never in a shadow map's shade, and a sunlit shaft's rock rim glowed whiter than the cave it bordered. The ground's own sun share under open sky is untouched. |
| 355e41c | Built walls (cobble, dressed, drow dark wall) draw laid stone: staggered courses, mortar, a shade per stone, a lighter upper edge; cobbles small and round. |
| c375d19 | `KIND_BUILT` (a quarter added to the soft kinds) marks paving, planks, plaster, roofs and built walls drawn soft; they take no grain or cracks. |
| 59a18d5 | A lone `dark_stone` merlon wears a four-sided spike; a `fae_lamp` is a slender dark post with a thorn, an arm and a hung violet globe. Look only: the tiles are unchanged. |
| 730ecc4 | Magma `rock_glow` 0.32 (basalt is nearly black, 0.1 showed nothing); lava rides the swell, slower and lower. |
| c417a1d | `corner_shot.gd region=fungal|crystal|deep_lake|magma` (the room in that region's rock, floor and wall, the region in meta) and `liquid=water|lava` (a basin whose floor steps down a column at a time into the liquid). |
| e5f6ae5 | Cheaper far glow (levels 4 and 5 once each through a soft knee) and detail (two noise reads). |

Dark stays dark: the face light is the light of open cells that are lit, so rock far from any lit cell is
black, the plain underdark has no rock glow, and the deep glow is the picture's, not the rules' (actors do
not take it: a creature in an unlit cell of a fungal cavern is still unseen). Rock and walls take the glow
alike, so an unlit pocket near a lit cavern does not stand out against its rock.

### API as built

- `ChunkMesher.opaque_bytes(snap)`, `KIND_BUILT`, `BUILT_WALLS`.
- `WorldView.ground_under(world, x, top)`, `GROUND_SCAN`; light textures mipmapped; `_light_rect` origin on 16.
- `BelowLook.rock_bytes(meta, rect, cell)`.
- Shader globals (`project.godot`): `gs_solid`, `gs_below_rock`, `gs_surface`, `gs_surface_on`. Hints of
  `gs_light_block` and `gs_light_sky` are now `filter_linear_mipmap`.
- `light.gdshaderinc`: `gs_light_lv`, `gs_face_levels`, `gs_cubic_uv`, `gs_levels_smooth`, `gs_deep_glow`;
  `lit.gdshaderinc`: `GS_MASKS_LV`.
- Data: `backdrops.json` `below.regions.*.rock`, `rock_glow`; `lighting.json` `shadows.low.sun_soft`.
- Tools: `corner_shot.gd region=`, `liquid=`.

### How the pictures read now

- **Crystal, at 0.4.** The ledge is lit pale stone through its whole depth, no streak; the pillar on the
  left is dark blue rock, not a black slab; the tunnel wall beside the ladder is coursed cobble, not
  pixel blocks. Good.
- **Crystal, at 0.75 and 0.25.** The diagonal slab is lit stone, smooth (an early try showed the mip
  grid as dark blotches inside it; two levels summed fixed that). At 0.25 the cavern reads; the deep
  road climbs through it in laid stone. Its cobblestone steps are still square blocks, as built tiles are.
- **Fungal.** The floor's rock is dark violet stone under the forest, no void. The best of the set still.
- **Lake.** The slope into the water is straight. The overhang is mossy stone, the bed and shores dark
  teal. The surface swells and glints; under it short vertical streaks of glint hang down, which read
  as light on water to me. The cavern over the water is still large and dim.
- **Magma.** Rock is a dark red-brown with its strata; ceilings show. The pool's rim is still a
  rectangle (the pool is one), and lava heaves only a little.
- **Plain torch-lit cave.** A tight, smooth rim of lit rock round the pocket; no stair; everything else
  black, as it should be. The ground above a cave under a village is continuous earth, no house shapes.
- **Shaft to the sky.** The cave under the shaft is the brightest thing; the rock round it a soft rim.
- **Towns (day, dusk, night), desert, mountain.** No dark shapes under houses. Ground and rock have
  grain and cracks at zoom 1 and 2; planks, plaster and roads stay plain.
- **Cave mouths, sinkhole.** Clean edges. At zoom 4 the sun's shadow edges are soft with a faint dither
  of Godot's filter (visible only that close).
- **Drow, medium seed 1 (x 4679, y 626).** Spires (region dressing), thorned battlements, webbed coursed
  walls, lamps on posts with hung globes. Moderate-to-good. Roofs are still flat under the spires, the
  furniture is the shared set, and on a dev world (no regions) there are no spires at all.
- **corner_shot**, every mode: clean. Water and lava basins: a straight slope into the liquid. The
  water's lighter top edge stops about a tile short of the slope.

### Measured

`look_shot bench=300`, CPU renderer (lavapipe), 1280x720, one Godot at a time, base an export of 92b1370:

| Scene | Base | Now | |
|---|---|---|---|
| Fungal | 34.95 ms | 39.98 ms | +5.0 |
| Crystal | 33.37 ms | 38.30 ms | +4.9 |
| Lake | 31.80 ms | 37.61 ms | +5.8 |
| Spawn town by day | 27.85 ms | 30.61 ms | +2.8 |
| Torch-lit cave, meadow | 27.01 ms | 31.00 ms | +4.0 |

That is +14-18% underground on the CPU renderer, after one round of trimming (+6 ms before). The cost by
piece, before the trim, on fungal: far glow 2.0 ms (now about 1), rock detail 1.1 (now less), face
light 0.8, wall spline 0.7, the rest masonry, lake, water and the CPU mipmaps. All of it is texture reads
per fragment; on a GPU it should be small, but GPU frame time is not measured here. The light images'
mipmaps are generated on the CPU at each refill (R8, the light rectangle) and the solid map's (512x256 R8)
when chunks land; neither showed up separately in the frame times.

### Gate

`tools/gate.sh` on e5f6ae5 (clean): import 0; **suite 10543 checks, 1 file failed**: `test_sim_world`
"strategic day for ~100 settlements under 4 ms" at 4.52 ms, the known one (it fails on base too, see
Gate above); all eight smokes NET SMOKE PASS; `test_m4_e2e,test_m5_e2e` unseeded three times, 210
checks ALL PASS each. `tests/test_look_polish.gd`: 26 checks.

### Open

- **Frame time** on the CPU renderer is up 3-6 ms (above). GPU not measured.
- **Light through a thin wall.** A wall's spline read reaches about a tile across a one-tile rock wall,
  and a rock face between a lit and a dark room shows half the light. Faint, and the rules are not
  touched, but it is a leak of the look.
- **The ground line** (`gs_surface`) is filled when the light rectangle moves, so digging at the surface
  leaves the sun share as it was until the camera moves on. `meta.surface` itself never follows digging.
- **Built tiles keep square corners**: the deep road's cobblestone steps read as a stair of blocks.
- **Water's top edge** stops a tile short where a slope meets it; the lake's under-surface glints are
  vertical streaks (I like them; judge by playing).
- **Magma pools** are rectangles by worldgen; the view only softens them.
- **Drow:** roofs flat, furniture shared, nothing on dev worlds (no regions).
- In contrast-stretched crops of dim fog, faint squares of a few pixels show. I think it is lavapipe's
  filtering precision on a heavily magnified texture, not checked on a GPU.
- `KIND_BUILT` rides in the kind's fraction: a new kind would have to keep the soft kinds' range.
