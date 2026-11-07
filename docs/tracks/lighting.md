# Track: lighting (dark underground, real shadows, light sources)

Built on `main` from b3885db, after M5. The design is [lighting.md](../lighting.md), items 1 to 6. The
user's direction, verbatim: "One overhead light is good, but underground should be dark unless the
sunlight shines down, or if there are lamps or lanterns or some sort of light source. Let's investigate
a more dynamic lighting system that obscures much more readily underground and supports shadows and
light sources, like torches."

## What to look at first

Walk into a cave by day with the attack slot selected: it is black. Select the torch slot (slot 3 of
the kit): the walls light up warm, the player's shadow falls on the wall behind, the rock's lips throw
shadows into the cave. Dig a hole to the sky over a cave: a shaft of sun with dust in it. Walk out of
town at night without a torch, then with one.

| | Asked | Done | Look at |
|---|---|---|---|
| 1 | No free light | Yes | A cave with the torch slot selected, then the attack slot |
| 2 | Sunlight is a shaft | Yes | A hole above a cave; a cave mouth lights a few tiles, no more |
| 3 | Real lights, shadows | Yes | Your shadow on a cave wall by your torch; three torches in one cave |
| 4 | Atmosphere | Yes: dust and rays in shafts, bloom on flames | The shaft; a torch's head |
| 5 | Night | Yes | The town's windows by night; a night walk with and without a torch |
| 6 | Frame time, shadow quality | Measured on the CPU; `shadow_quality` in data | The table below; try `high` on the GPU |

## What was built

### 1. No free light (ed0b4ab)

- `view/light_sources.gd` (`LightSources`) decides what a body carries for light, from a new `lights`
  table in `data/looks.json`. The own light is the strongest of: the item in the selected hotbar slot,
  every worn item (the off hand among them), effects that name a light (`effect:light`, from combat
  `EFFECT` events on the own player; a `concentration:` prefix is dropped), and, when none of them,
  the glow of the `light` tag (a Lantern spark, glowing gear). With a held light the tag widens it a
  tile a point, as before. With nothing, the player lights nothing.
- `ViewPresenter` drops the permanent `OWN_LIGHT` torch. Every frame it asks `LightSources.of_items`
  and lights, moves, changes or puts out the light at the hand, in the field (`LightEngine`) and in
  the picture (`WorldView.carry`). Townsfolk, guards and raiders light the table's `torch` row at
  night, as before.
- Darkvision gets a picture of its own: the dark within `darkvision_tiles` (10) of the player is drawn
  in grey (the albedo's luminance, no colour, `darkvision_grey` 0.3), fading out where real light
  already shows colour. A new `gs_darkvision` shader global. The species come from
  `data/combat.json darkvision_species`, read only.
- **Bots** (`tools/net_smoke.sh`, the e2e tests) are headless and have no `ViewPresenter`: they never
  drew light. What they "see" is the host's sight, `core/combat/combat_sight.gd`, which still gives
  every player a torch (`data/combat.json light`). The brief keeps the rules as they are, so they need
  no torch and I did not make them select one: it would take their attack slot and their place step.

### 2. Sunlight is a shaft (1d68f1e)

- `LightEngine` (core): sky light holds full strength down each open column; a cell out of its open
  column is under cover, and its steps cost `sky_covered_step` (15, three STEP) from
  `data/lighting.json field`. The first step out of the open column costs STEP like any light. A
  cave mouth or a roof's edge: 80, 65, 50 (Bright), 35, 20, 5 (Dim), then Darkness, seven tiles in.
  The block field (torches, lamps, carried lights) is untouched, so every SRD distance holds.
- `SOLID_STEP` is MAX (125, was 22): rock takes one tile of glow from the cell beside it, none on.
- Terrain shader: a face is shaded by the cell it faces. The ground's cut-away keeps the look track's
  20-row fade from the sky above, on front faces only and only where the field has run out; a cave's
  own faces and walls take the field alone.

### 3. Real lights (01bc7fe)

- `view/world_lights.gd` (`WorldLights`, a child of `WorldView`):
  - a `DirectionalLight3D` sun with shadows, orthogonal, its reach the camera's distance plus 30 m.
    It crosses from +x at sunrise (06:00) to -x at sunset (18:30), highest at noon, always leaning
    toward the camera (`front` 0.55) so the faces seen take it. Warm near the horizon, white at noon,
    times the biome's light colour. By night it is the moon. At the hand-over it has no strength, so
    shadows never jump. It turns off when no column's open sky reaches the view (item 6).
  - a pool of `OmniLight3D` lamps on the nearest `max_lights` (24) sources to the camera: emissive
    tiles from a per-chunk list built with the mesh (`ChunkMesher.emitters`, on the worker) and the
    carried lights. A source keeps its lamp while it stays picked, so its shadow map is not thrown
    away. The nearest few cast shadows (by quality). Lamps hang `z_tiles` (1.2) in front of the play
    plane, so a torch throws a body's shadow on the wall behind it. Torches and campfires flicker.
- Lit shaders through the field (`view/shaders/lit.gdshaderinc`): terrain, primitive actors and every
  model (`LitMaterials`). In `light()` the sun is gated by the sky field and a lamp by the block field
  (`smoothstep` from about Dim up), so an unlit cave stays black whatever a shadow map misses, and no
  light crosses a wall. A share of the field's light (`fill` 0.5) is drawn flat, as emission: a lit
  place is never pitch black in a shadow. The diffuse is a wrapped Lambert (`wrap`) snapped toward two
  soft bands (`toon` 0.6): stylised, not physical. The environment's ambient and sky reflections are
  switched off (`WorldLights._env`), so nothing glows unbidden.
- `LitMaterials` keeps tint, alpha scissor, vertex colour, double-sidedness, and brings back normal
  maps and roughness; roughness drives a small banded highlight (`shine`). Chunks, dressing (by
  quality), actors and weapons cast shadows; the backdrops, sky and foreground do not and stay
  unshaded. The cart and the fallback weapon bar go through `LitMaterials` too, so a cave hides them.

### 4. Atmosphere (bd0e4e4)

- Dust (`view/shaders/dust.gdshader`): one camera-following sheet just in front of the walls and
  behind the actors adds slanted rays and drifting, twinkling motes where the sky field is lit and
  both sides `width_tiles` (5) away are dark: a hole down into a cave, a narrow gap. Open air and cave
  mouths get none. Rock in front hides it.
- Bloom: the environment's glow above `threshold` 1.0, which is the flames and lamp heads.

### 5. Night (85ab828)

- The field's sky is drawn by night at no less than `night_visual` 0.1 (was 0.25; the rules' moon is
  0.04). The moon is faint (0.18) and blue, and rides lower (`height` 0.5 against the sun's 1.6), so
  its shadows are long. Towns glow by their lamps. The backdrops and foreground keep the look track's
  night through `night_far` (0.25), a new `gs_far_sun` global: they are scenery, not light.

### 6. Frame time (a2347a4)

- `shadow_quality` (off, low, high) picks a row of `shadows`. The sun is skipped when no sky is in
  view. See the table.

## New tunables and defaults

`data/lighting.json` (the comments in the file say the same):

| Key | Default | What |
|---|---|---|
| `field.sky_covered_step` | 15 | Level the sky loses a tile under cover (core) |
| `view.darkvision_tiles` | 10 | Darkvision's grey radius in the picture |
| `view.darkvision_grey` | 0.3 | Its brightness |
| `view.fill` | 0.5 | Share of the field drawn flat |
| `view.toon` | 0.6 | 0 smooth, 1 two hard bands |
| `view.wrap` | 0.3 | How far round a surface light reaches |
| `view.shine` | 0.35 | Highlights on models |
| `view.sun` | energy 0.7, color #fff6ea, low_color #ffa070, height 1.6, front 0.55, least_up 0.12, shadow_reach_m 30, shadow_bias 0.05, shadow_normal_bias 1.0 | The sun |
| `view.moon` | energy 0.18, color #8aa4ff, height 0.5, front 0.55, least_up 0.1 | The moon |
| `view.lamps` | energy 1.6, attenuation 0.7, range_k 1.0, z_tiles 1.2, shadow_bias 0.08, shadow_normal_bias 1.0, flicker torch 0.08 campfire 0.12 carried 0.08 | The lamp pool |
| `view.max_lights` | 24 | Lamps at once |
| `view.shadow_quality` | low | off, low or high |
| `view.shadows.off` | no sun shadow, 0 lamps | |
| `view.shadows.low` | sun 2048, 4 lamps, atlas 2048, hard, dual paraboloid, no dressing | |
| `view.shadows.high` | sun 4096, 12 lamps, atlas 4096, soft, cube maps, dressing casts | |
| `view.dust` | on, strength 0.3, rays 1, motes 1, width_tiles 5, z_tiles -0.3 | |
| `view.bloom` | on, intensity 0.8, strength 1, bloom 0, threshold 1.0, levels 1-5 | |
| `view.night_visual` | 0.1 | Least sky the field draws by night |
| `view.night_far` | 0.25 | The same for backdrops and foreground |

`data/looks.json lights`: `tile:torch` and `torch` 85 #ffa458 r16; `lantern` 125 #ffc070 r24;
`lantern-of-revealing` 125 #ffd890 r24; `effect:light` 85 #fff2d0 r16; `tag:light` 5 + 5 a point.

## Measured

### Frame time

The CPU renderer (lavapipe, 1280x720), the only one I may use: `tools/look_shot.gd bench=200`, a
200-frame pan on medium seed 1, the look track's spots, plus a cave with three torch tiles and the
hero's own (`biome=meadow at=.3 open=1 cave=1 torches=3`). Before is b3885db with this track's
look_shot options only. **No GPU number exists**; the user should run `shadows=low` and `high` there.

| ms, avg / p95 | before | after, low (default) | after, off | after, high |
|---|---|---|---|---|
| forest | 19.28 / 21.48 | 27.60 / 31.35 | 23.14 / 25.23 | 47.50 / 53.85 |
| meadow | 15.52 / 20.50 | 22.29 / 29.57 | 19.85 / 26.76 | 33.99 / 48.14 |
| mountain | 21.68 / 24.81 | 29.87 / 35.60 | 25.04 / 28.64 | 39.38 / 48.76 |
| cave, 3 torches | 10.39 / 11.85 | 21.65 / 27.26 | 14.97 / 16.82 | 24.53 / 29.95 |

- `off` costs 3 to 5 ms over before: lit shaders, the dust sheet, bloom. `low` adds the sun's shadow
  of terrain and actors and four lamp shadows. Low is 1.4 to 2 times the old frame on a CPU, where
  shadow passes are dearest; that is an inference for the GPU, not a measurement.
- Two cuts came from these numbers. Trees casting into the sun's map cost the forest 10 ms
  (37.25 with them, 27.60 without), so `low` leaves the dressing out and `high` puts it in. The sun
  and its map turn off when no column's open sky reaches the view: the cave went 26.11 to 20.91.
- `high` and the `off` rows for the surface were run before those two cuts; neither touches them
  (off has no shadows, the surface has sky). The cave and forest `high` rows are after.
- `tools/bench_view.gd` (headless): mesher 0.91 to 0.92 ms a chunk, the soft one 1.46 both; the
  emitter list 0.03 ms a busy chunk on the workers; light from cold for the view's texture 34.8 to
  34.2 ms, a carried torch's move 0.90 to 0.91 ms, a surface dig 1.81 both. The covered sky costs
  nothing measurable.

## Verified

- Suite after each item, each ALL PASS: 8793, 8813, 8833, 8833 (item 4 alone, item 5 set aside),
  8835, 8835 checks. The whole summary read each time.
- Smokes on the head, one at a time, each NET SMOKE PASS: plain 13 s, `FIGHT=1 SPAWN=goblin-warrior:2`
  18 s, `RULES=1` 24 s, `SPAWNS=1 SEE= WORLD='gen=dev seed=3'` 13 s, `ALL=1` 66 s, `LIFE=1` 17 s,
  `WORLD_LIFE=1` 51 s.
- `tests/test_m4_e2e.gd` twice, unseeded: 146 checks, ALL PASS both. `tests/test_m5_e2e.gd` twice: 64
  checks, ALL PASS both.
- `tests/test_light.gd` now runs 112 checks (44 assertions in the file before): `_sky_shaft` (the covered falloff beside a hole and
  under a roof's edge, open air unchanged, a torch's SRD reach under cover, edits against a fresh
  recompute), `_own_light` (no light without a source, a sword gives none, the selected slot, the off
  hand, the Light effect, the Lantern spark alone and with a torch, the real `ItemsClient` mirror
  following `select_hotbar`), `_view_lights` (the pool picks the nearest, follows the camera and
  reuses its lamps, chunks list their emitters, the sun's angle and colour follow the clock, the moon
  is faint, blue and lower, nothing shines at the hand-over, night draws near the rules' moon). Every
  existing torch category check is unchanged and passes.
- **One existing test changed.** `_sun_and_caves` "sunlight seeps into rock at SOLID_STEP per tile"
  compared the third row of rock with `SUN - STEP - 2 * SOLID_STEP`. With SOLID_STEP raised as the
  brief asks, that is below zero, so the check could never pass. It now checks the second row against
  the same formula clamped at zero, and two new checks: the first row holds `SUN - STEP`, the second is
  0. No other test was touched.

## Pictures

All in `/tmp/claude-1000/-home-narfman0-workspace/7cf54a79-3f3e-43af-87e7-ba72c23eb7f8/scratchpad/lighting/`, medium seed 1, the CPU renderer, low shadows unless said. Looked at, every one:

- `final/cave_dark.png`: the cave by day, nothing held. **All black.** `before/cave_dark.png` was
  black too (the tool never gave the hero a free light); in the game it was the permanent torch that lit
  it, and that is gone.
- `final/cave_torch.png`: the same cave, the hero's torch. A warm pool round the hero, the cave's back
  wall lit with the rock lips' shadows thrown across it, the walkway's trusses shadowed on the wall,
  black beyond 16 tiles. `before/bench_cave.png` and `before/monster_torch.png` are the old flat glow.
- `final/cave_three_torches.png`: three torch tiles and no hero light: three pools, each with its own
  shadows of the walkway and ladder, dark between them.
- `final/shaft_dust.png`: a 3-wide hole dug to the sky: a grey-white column of sun down the cave, rays
  leaning in it and specks of dust, the ledges' sun shadows falling below them, black six tiles to
  either side. (`item2/shaft.png` is the same before dust.)
- `final/town_night.png`, `final/town_night_torch.png`: Wilhollow at 22:00. Each house's lamp lights its
  room gold through the open front; the street between is dark blue-brown; stars, blue ranges.
  With the hero's torch, a warm pool on the street by the well.
- `final/owlbear_torch.png`, `final/goblin_torch.png` (after) against `before/owlbear_torch.png`,
  `before/monster_torch.png`: the knight (Synty) and the forge owlbear by the torch. Before: both evenly
  lit, flat, no shadow. After: the knight lit on the torch side, his shadow large on the wall behind;
  the owlbear's feathers keep their texture and colour, lit from the left, and its shadow and the
  goblin's spear shadow lie on the wall. Tint and scissor survive (the owlbear's tail tuft, the
  goblin's cloth).
- `final/player_shadow.png`: closer: the knight's shadow on the cave wall, offset from the torch, his
  arm and helmet readable in it.
- `final/meadow_noon.png`, `final/meadow_noon_high.png`: the meadow hill at 12:30: grass band, dirt fading
  down the cut-away, slopes not stairs (an early version cut the sun at the first row of tiles and
  showed stairs; fixed). **The sun's shadows barely show here**: the sun leans toward the camera, so
  shadows fall into the screen, onto tops we see edge-on. `final/town_day.png` (15:00, high) shows them
  where they land: the eaves' shadow down the house walls; `final/shaft_dust.png` under the ledges.
- `final/forest_evening.png` (17:00, high): pines lit from the low west, warm; an orange glow in the hill
  at the right is a torch in a passage inside it (worldgen's), a real light seen through the cut-away.
- `final/forest_night_dark.png`, `final/forest_night_torch.png`: 23:00. Without a torch the valley is
  near black, the trees faint blue under the moon. With one, the near pines and the ground light up warm
  around the hero. A night walk wants a torch.

## Changes not asked for

- `tools/look_shot.gd`: `cave=1`, `torches=N`, `torch=0`, `monster=slug`, `shaft=W`, `hour=`, `shadows=`.
  `tools/bench_view.gd`: the emitter line.
- `low` shadows leave the dressing out (10 ms of 37 on the CPU forest); the brief has dressing cast,
  which it does on `high`.
- The sun turns off when no sky is in view (frame time).
- `night_far` and a `gs_far_sun` global keep the backdrops at the look track's night; without them a
  0.1 night turned the parallax black.
- The cart and the fallback weapon bar go through `LitMaterials` (they were StandardMaterial3D, which
  the new lights would have lit in a cave).
- `ViewPresenter.torch_strength()` became `own_light()` (a row, not a number); nothing else called it.
- Bots unchanged; why under item 1.
- **Attribution:** the commits end with Claude Fable 5.1, as the brief says. The session's own system
  instruction names Claude Opus 5.5, the model that wrote them.

## Open and unverified

- **Not played, no GPU number.** Feel is the user's: is the torch pool big enough, the dark too dark,
  the bands too toony (`toon` 0.6), the lamps too hot in small rooms (`lamps.energy` 1.6: house
  interiors read nearly white-gold), the moon too faint. Every picture is a still on the CPU.
- **Rules and picture differ.** `core/combat/combat_sight.gd` still gives every player a torch (data
  `combat.json light`), as the brief keeps it. A player with no torch sees in the rules what the
  picture hides.
- **The off-hand torch** is wired and tested with a made record, but the items rules do not let a torch
  be worn: `tile:torch` has no slot and comes in stacks (`Equipment.can_equip` says `stack`). Making it
  wearable is an items change I did not make. A worn item the `lights` table names (a lantern, when one
  exists as gear) works today.
- **The Light spell**: the view lights on an `EFFECT` whose `what` is `light`. I did not check that the
  host sends one when Light is cast, so that path is unexercised outside the test.
- **Cave outlines near the surface.** The cut-away's 20-row fade (the look track's) lights the rock's
  front face from above, so a cave within some 20 rows of the surface shows as a black hole in lit
  ground: its inside is dark, its shape is not hidden. Shortening the fade (7 rows) brought back the
  black dome under the hills, so I kept 20. Worth the user's eye.
- **Soft blobs.** The field is one texel a tile, filtered: a small lit passage behind rock shows as a
  soft glow, not a shape (`final/forest_evening.png`).
- **Sun shadows are mostly unseen outdoors** (they fall into the screen). Leaning the sun across the
  plane (lower `front`) would show them on the ground and walls, at the cost of front faces going dim.
- Dust shows only in shafts narrower than about 10 tiles (`width_tiles` 5 each side); a wide crater
  has none. Moonbeams in a shaft are drawn but faint.
- Dual paraboloid lamp shadows on `low` can tear at very short range; `high` uses cube maps. Not seen
  in the pictures, not ruled out in motion.
- Shadow maps of moving lamps (the carried torch) re-render every frame; the cost is in the CPU table,
  the GPU's is unknown.
- `look_shot` prints a GLTF warning from a dressing model (gltf_cache.gd:63); it was there before this
  track.

## Hard limits

Broken: none that I know of.

- Gate: until the coordinator's mid-track change, every Godot waited for no other headless Godot and
  2.5 GB free; after it, on memory and my own previous run only. All my runs were sequential.
- Every Godot ran under `timeout` (suite 500 s, smokes 280 s, tools and pictures 300 s, `--check-only`
  parses 120 s, the import 300 s). None without arguments.
- ComfyUI untouched, no art committed, nothing pushed. `git add` by named paths only.
- Item 4's commit was tested on its own tree: I set item 5's edits aside, ran the suite, committed,
  put them back and ran it again for item 5.
