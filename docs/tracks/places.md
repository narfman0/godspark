# Track: Places (M4 wave 1)

Branch `ws/places`. Settlements are real places in the tiles, roads join them, and they grow
and fall into ruin as the sim says. Tiles are the truth; Synty pieces are the skin.

## What was built

| File | What |
|---|---|
| `data/places/styles.json` | culture -> style; per style: palette (tile names), roof (`gable` / `flat` / `tent`, step, overhang), `tall` (chance of a two-storey lot in towns and cities), kit, plan. Plans: centre lot by tier, lots outward from the centre with the lowest tier each is built at, end gates |
| `data/places/buildings.json` | building templates as tile grids with a legend (see its `_comment`): home, home_tall, smithy, store, store_tall, tavern, hall, shrine, square, market, gate |
| `data/places/kits.json` | per style: piece role -> dressing id (the skin) |
| `core/world/place_styles.gd` | `PlaceStyles`: reads the three files, parses templates (cells, anchors, door) |
| `core/world/place_builder.gd` | `PlaceBuilder`: `plan()` a place for a site, `set_lot()` / `lot_writes()` tile writes and dressing for a lot built or ruined, `building_record()`, `refresh_buildings()`, `changes_for(place, tier)`, `lot_rect()` |
| `core/world/worldgen/stage_places.gd` | stage `places` (after `routes`) |
| `core/world/worldgen/stage_roads.gd` | stage `roads` (after `places`, before `dressing`) |
| `core/host/place_keeper.gd` | `PlaceKeeper` (`WorldHost.places_keeper`): growth, founding, ruin, arrival notices |
| `core/world/places.gd` | added `street_at(world, x)`, `place_at(world, x, y)` |
| `tools/place_shot.gd` | screenshot of a place or a road bridge (soft_godot) |
| `tests/test_place_gen.gd`, `test_roads.gd`, `test_place_keeper.gd` | see Tests |

Shared files touched (small, additive): `data/tiles.json` (tiles 96-111, walls 40-44),
`data/dressing.json` (22 ids appended), `core/world/worldgen/world_gen.gd` (two stages),
`gen_context.gd` (`places`, meta), `stage_dressing.gd` (keeps building pieces, keeps scatter
off place streets, skips band `place`), `stage_surface.gd` (flats 96-150 wide on worlds 1024
wide and up; the RNG call count is unchanged), `core/host/world_host.gd` (`places_keeper`,
`find_spawn` uses the street), `core/monsters/nav_follow.gd` (a body caught on a ladder while
dropping past it climbs on down: a two-line fix the ladder stairwells needed),
`core/monsters/spawn_director.gd` (`safe_ok` uses the place rect), `view/chunk_mesher.gd`
(walkways drawn as slabs, ladders as rails), `view/actors/dressing_view.gd` (`still`, `turn`),
`game/main.gd` (`spawn_for`), `tools/worldmap.gd` (paths and places), `tests/test_looks.gd`,
`tests/test_worldgen.gd` (route keys may carry `path`, `rough`).

### Tiles (append-only; Places owns 96-127 and walls 40-55)

Tiles: 96 timber, 97 plaster, 98 dressed_stone, 99 thatch, 100 shingles, 101 dark_stone,
102 logs, 103 canvas, 104 planks, 105 road, 106 lamp (emit 13), 107 awning (one-way),
108 elf_wood, 109 leaf_roof, 110 fae_lamp (emit 14), 111 bridge (one-way walkway).
Walls: 40 plaster_wall, 41 dressed_wall, 42 elf_wall, 43 dark_wall, 44 canvas_wall.

## How a place is made

- **The sim decides culture and tier.** The stage builds `WorldSim.from_meta` on the same
  sites, routes and seed the host will use, so the place has the sim's culture and starting
  tier. **No change in `core/sim`.** A test checks they agree. Sites the sim leaves empty get
  a place with tier `""` (levelled and laid out, nothing built) for a later founding.
- **Lots.** `PlaceBuilder.plan` walks the style's plan from the centre outward, alternating
  right and left, inside the usable span (contiguous ground needing at most 12 tiles of cut
  or fill, no road or ramp, no cave just under the ground, and short of the midpoint to a
  neighbour less half the climb between them so the road has room). A lot that fits on
  neither side is skipped. Gates go at the two ends. Every lot of the full (city) plan is
  recorded; the tier says which are built.
- **The street** is the site's feet row from end to end. Every building stands on it with
  4-row doorways at both ends, so the street (and the road) runs through every ground floor:
  a wagon passes, and people walk in through the door. Upper floors are solid floors with a
  3-wide ladder shaft and one-way walkway margins (use the Traversal track's `stairs` tile
  for `H` after the merge). Rooms have 3 clear rows; ground floors 5.
- **Levelling.** Surface: cut down to the street, fill up to it, then 1-per-column ramps
  back to the natural ground. Caverns: clear the building envelopes, ramp the floor back
  where no road or ramp runs.
- **Tiers.** hamlet: the square (well, shrine post) and 3-5 homes; village: + tavern or
  hall, smithy or store, shrine; town: market on the square, the other two, more homes, a
  gate at one end, two-storey lots; city: more of each, gates at both ends. Raider camps
  (goblinoid, kobold, gnoll, bandit, orc) have tents and a palisade gate at both ends from
  the start. Narrow ground drops the outer lots, so many towns are short of their full list.
- **Styles.** human (timber, plaster, thatch gable), halfling (steeper thatch), dwarf
  (dressed stone, flat roof with crenels, cobbled street), elf (pale wood, leaf roof with a
  long overhang), drow (dark stone, flat roofs, fae lamps), raider (canvas tents, log
  floors). Fallbacks: dragonborn and tiefling human; gnome halfling; goliath dwarf.
  Unsettled cave sites default to dwarf, deeper ones to drow; a founder restyles the site.
- **The skin.** Pieces in the templates name roles (bed, table, forge, anvil, counter, stall,
  well, statue, throne, candles ...); the style's kit maps them to dressing ids. A piece is
  placed only where its footprint fits the template. Every piece stands behind the actor
  plane and no front pieces exist, so a building always reads as a cutaway: back wall,
  rooms, roof. Dressing records follow the existing rules (removed when support is dug).
  Lamps inside every room glow after dark.

## Roads and route paths

- `road` routes: graded from one place's street end to the next: a closing (max then min
  filter, radius 7) fills dips narrower than 14 columns, the profile stays within reach of
  both ends and steps at most one tile per column; cut where the ground is higher, filled
  up to 3 where lower; deeper, or over a ramp tunnel, a `bridge` walkway. Surface `road`
  tile; 4 clear rows. A signpost by each end, a milestone every 64 columns.
- The ascent's surface leg (ramp mouth to its town) is graded the same way unless a road
  already runs there. A surface ruin site under a graded road moves to the new ground.
- `meta.routes[i].path`: feet cells. Roads: from street end to street end (in a-to-b
  order). Deep routes: a breadth-first walk over feet cells, one tile up or down per column;
  if none exists, a jumping-and-falling walk (24 down, 6 up), else a walk through open cells
  ignoring gravity; both flagged `"rough": true`. On dev seeds 1-3 every deep road between
  two deep towns is a clean walk except where a ramp crosses it (seed 2); every ascent and
  portal route is rough today (holes in the ramps). They become clean when the Traversal
  pass makes them walkable; the stage needs no change.

## Growth and ruin (`PlaceKeeper`)

Once a second (host thread): for each place, the wanted tier is the sim settlement's tier,
or `""` when the sim has none. A founding (a settlement on a place with nothing built)
restyles the place for the founder and builds the hamlet lots. Tier up builds lots; tier
down or abandonment (or a sack that empties it) turns built lots into ruins: walls,
floors, roof, ladders and lamps gone, the back wall jagged, one-tile rubble, ruin pieces
(broken wall, rubble heap). The street stays open. A change waits while any player is within
70 x 45 tiles of the place rect and is applied as soon as none is (a long sleep may apply
several). Writes go through `set_fg` / `set_bg`, so clients get TILE events and saves
follow; lot dressing is replaced and sent as OBJECTS; `meta.places` is updated (saved with
`world.json`). Old worlds without places: the keeper does nothing.

## Arrival and spawn

A player who walks into a settled place gets a Rules `NOTE` (no protocol change; the client
already shows it as a toast): "Millburrow, a halfling town of 633 souls" (name, culture,
tier and population from the sim). New players start on the square of the first settled
surface place. `WorldHost.find_spawn(x)` returns the street row inside a place (monsters
spawned by tools no longer land on roofs).

## For Life and Deals

Read `Places` only; nothing new is needed. `buildings[i]`: `kind` (home, smithy, market,
tavern, shrine, gate, hall, store, ruin; a ruin has `was`), `rect`, `door`, `anchors`
(smith, merchant, keeper, priest, guard, townsfolk; townsfolk also at home doors), `lot`.
A place also has `street: [x0, x1, y]`, `style`, `lots`. Tier `""`: nobody lives there.
Route paths are feet cells; check `rough` before walking a wagon on one.

## Numbers

- Worldgen time added on dev (2048x1024), seeds 1-3: `places` 48-62 ms, `roads` 108-203 ms
  (most of it the deep-route walks that fail and fall back), total 933-1038 ms.
- Tests: 3251 checks (3082 before this track).
- Assets: 22 dressing ids from Dark Fantasy, Fantasy Kingdom, Dungeons Realms, Goblin War
  Camp and Elven Realm; about 13 MB fetched.

## Open issues

- Towns are short: ground limits most places to 100-240 columns, so many towns and cities
  lack their full list; the plan drops outer lots first. Wider or terraced sites would help.
- The skin is furniture and props; walls and roofs are the tiles. Synty wall and roof
  panels stretched over buildings were not done (they need per-record widths).
- Halflings and gnomes use the human-sized pieces (no per-culture piece scale yet).
- Ladders stand in for stairs. Upper floors need the ladder or a jump.
- Rough deep routes (above). Ruins do not yet keep a name for the arrival notice.
- Conquest by another culture keeps the old style until the place is refounded.
