# Track: Passability (M4, second pass)

Branch `ws/passability`, cut from main 9c5a574 (Traversal, Places and Life merged; Life off by
default). The user asked: "lets make sure areas are more passable". The Traversal track's
first pass (docs/tracks/traversal.md, item 4) got close; this pass finishes what it could.
One commit per item.

## What was wrong

Measured on 9c5a574 before any change (this machine, with other work running):

- **The follower did not take the paths it was given.** Walking a planned path without
  replanning, a Medium body arrived on 48% of cave paths and 20% of long site-to-site paths.
  `tools/nav_probe.gd` logged every failure with the edge kind, a picture and an input trace.
  The causes, in order of how often they struck:
  - jump take-offs from a body still holding the ladder or rope it climbed (climbing *and*
    standing: the follower never pressed jump), and a ladder step's overshoot answered with
    the opposite input forever (up, down, up);
  - jumps replayed open-loop: any take-off off its spot or with speed drifted off the arc;
    jump landings planned on a sliver of a corner, and at the very top of the arc;
  - platform drops pressed once, before the body stood over the drop (it jumped instead),
    a drop's air steering overshooting narrow ledges, and the planner letting a drop fall
    past a walkway one row down that the controller lands on;
  - stairs: the follower stopped at every tread (reversing on a staircase walks it down),
    the planner allowed a lift for a tread anywhere under the new node (the controller looks
    only at the leading column), and a body on a staircase keeps to the treads where the
    planner thought it walked level;
  - climbers sent down through a walkway in their middle column; wall climbs planned with no
    wall; a cling edge never "arrived" while the body hung on a rope;
  - the roads stage bridged sloping road over air with walkway planks, which nobody can
    walk up (a sideways jump chain was the only way).
- **Sites**: 154/160 on the nav graph (every site in 5 of 10 dev worlds); 79/81 small. Places
  and roads ran after the passages stage and changed the ground under it; ramps were paved
  only over rock, so they had holes wherever they crossed a cave, and Places' building lots
  cleared the ascent's first rows inside the deep town. Every ascent and portal route was
  flagged rough.
- **Generation**: the passages stage analysed the whole world twice (about 0.9 s on dev).

## What changed

### 1. The follower takes the paths it is given (`core/monsters/nav_follow.gd`, `nav.gd`, `nav_search.gd`)

- Jumps: the recorded runs keep the body's path tick by tick (`tx`, `ty`, `peak`). In the air
  NavFollow tries a few steerings on a copy of the body each tick and keeps the one nearest
  the arc (`_track`); a take-off waits up to 1 s to line up (simulated braking, W to climb back
  up stairs it ran down), and a body standing in a ladder at the take-off leaves it sideways,
  or jumps from it when the take-off node holds the ladder.
- Drops, platform drops and the ends of runs before a jump or drop brake by simulation
  (`_aim`, `_approach`); a platform drop stands over the drop first and presses again if it
  did not go through, drops on through a walkway part of the way down, and a climber held up
  by a walkway on its ladder lets go sideways and drops.
- Stairs are run like walks (a carrot through the flight).
- Recovery (`_resync`): a body standing on a path node a little ahead (or a column or row off
  it) carries on from there; one behind goes back to it (at most 6 times per path, then the
  path fails and the caller replans, as brains always did).
- Planner (matching the controller): a jump landing needs half a tile of the recorded box
  over floor (`MIN_SUPPORT`) and 0.6 rows of arc above it (`MIN_CLEARANCE`); a STAIRS lift
  only for a tread in the leading column; on a staircase (standing on treads only) no level
  walk where the controller would step; platform drops land on the first floor below; a
  climber is not sent down through a walkway or tread in its middle column; vertical cling
  edges need a wall; CLING and LADDER arrivals accept either climbing state.
- Roads (`stage_roads.gd`): a sloping span over air is a flight of stairs, not walkway planks.
- `tests/test_monster_nav.gd` `_caves`: the "real body follows found cave paths" bar is
  **9 in 10 for Medium** (it was 8 in 10 before the passages stage, 7 and then 6 since) and
  **3 in 4 for Large**: the test world gives Large only 8-10 planned paths, so one miss moves
  it 10-12 points; over 6 seeds without replanning Large follows 91% and Medium 96%.

### 2. Every site and route end, every seed (`stage_passages.gd`, `world_gen.gd`)

- The `passages` stage now runs **after `roads`** (last of the terrain stages, before
  `dressing`), so it sees every settlement, road and ramp as they will be. It floors ramps
  with stair treads where they cross caves (outside building lots), joins every component
  as before, then takes the targets: every site and both ends of every route
  (`targets(c)`). A second look on the world as it now is checks the targets first, joins
  any that are apart, rejoins what later joins cut apart, and looks again (up to
  `REACH_ROUNDS`) until a look needs no target join.
- Passer's moves were made a subset of the nav graph, checked edge by edge against a nav
  flood (87 disagreeing moves on dev seed 3 before, 3-4 after): jumps land with floor on the
  side the body comes from, running jumps need two rows over the box (`ACROSS_ROOM`), ladders
  join only the box whose middle column holds them. Targets are found at the same nodes the
  nav check uses (`NEAR`).
- Never cut: places (street plus 30 rows over it), the Places track's tiles (ids 96+),
  bedrock, paved floors, floors joins laid, and the floor under every target
  (`Passer.protect`). A shaft cannot overwrite a protected floor with its ladder either.
- Deep routes: flagged rough ones are walked again; where the rough walk steps more than a
  row a short flight of treads is laid (`_flight`); failing that the route is **graded**
  (`_grade`): the cheapest one-row-per-column walk along the route's line (town end, deep
  road, the ramp's own path, the other end, plus the old path) where cut rock and laid treads
  cost, then built (never through built tiles; inside building lots only walking). A clean
  route loses `rough`.
- `stage_deeps.gd` keeps each ramp's feet cells (`ascent.path`, `portal.path`) for this.

### 3-6. Point-to-point, joins, speed

- Point-to-point above 85% came from items 1 and 2 (the planner's window was not the
  bottleneck any more: Medium plans 229 of 240 pairs and follows 98% of them), so the
  planned hierarchical search was not built.
- Fewer joins: pockets a new feature runs through are joined by it (`_absorb`), and the
  feature becomes a target for later joins (`_virtual`: a pocket beside a shaft gets a short
  way into it rather than a parallel shaft); a cut through another way's floor leaves a plank,
  so it is not cut in two (fewer rejoins). Tried and dropped: not joining pockets under 8
  spots (point-to-point fell to 81%), preferring slopes to shafts (80-86%), dropping the
  second look (86%).
- Speed: climbable runs found with a native `PackedByteArray.find`; jumps across stop at the
  first blocked column and jumps up at the first blocked row; the nearest-network search goes
  outward in rings and stops when nothing farther can be cheaper; a component that found
  nothing is retried only when something was joined near it (the search ran 11 000 times
  per world, 0.4 s). Two full analyses per world instead of four.

## Numbers (before: 9c5a574; after: this branch; same machine, same day)

| | before | after | target |
|---|---|---|---|
| point-to-point, Medium, 240 pairs on 10 seeds (`cave_nav mode=pairs`) | 156 (65%), 202 planned | **225 (94%)**, 229 planned | above 85% |
| point-to-point, Large climber, same pairs | 62 (26%), 91 planned | 79 (33%), 89 planned | 43% or better |
| follower, planned cave paths, no replanning (`nav_probe`, 6 seeds) | Medium 48% (4 seeds) | Medium 96%, Large 91% | 90% |
| follower, planned cave paths, with the test's 3 replans | Medium 77% (156/202), Large 68% | Medium 98%, Large 89% | |
| sites + route ends on foot, nav graph, dev 10 seeds (`passability_sweep`) | sites 154/160, all in 5 of 10 | **328/328 targets, all in 10 of 10** | every site, every seed |
| same, small 3 seeds | sites 79/81, all in 1 of 3 | **166/166, all in 3 of 3** | |
| real-body site walks from the spawn, dev 10 seeds (`cave_nav mode=sites`, 4 replans) | 34/160 (21%) | **150/160 (94%)**, every site in 7 of 10 | above 85% |
| long site paths walked without replanning (`nav_probe mode=sites`, 3 seeds) | 9/44 (20%) | 38/45 (84%) (mid-pass) | |
| rough deep routes | every ascent and portal route | 5/80 dev, 1/42 small | none |
| joins per dev world (10 seeds) | 762: rope 357, ladder 163, steps+bridge 194, stairs+bridge 22, steps 12, bridge 12, passage 2, stairs 1 | 752: rope 322, ladder 117, steps+bridge 249, stairs+bridge 18, steps 25, bridge 15, passage 2, stairs 1 (incl. about 4 for sites) | fewer, clearly |
| generation, dev (avg 10 seeds) | 2.1 s | 2.5 s | about 1.3 s |
| generation, small (avg 3 seeds) | 6.1 s | 8.6 s | about 3.5 s |

The traversal track's own numbers (1.8 s and 5.4 s) were measured on a quieter machine;
both columns here are from today's runs. Before the first commit the planner was also looser
(it counted jumps the body then failed), so "planned" fell while "reached" rose.

### Where the time goes (dev seed 3, after)

Of 2.3 s: caves 370 ms, cave_steps 170, layers 110, roads 70, places 70, caverns 65, the rest
of the earlier stages 40; `passages` about 1.3 s: two full analyses (spots 140 ms and moves
140 ms each), joining 260 ms, the second look's rejoining about 100, the target check after
it about 300 (a third analysis, needed in most worlds because the second look's target joins
must be checked), route grading 80 ms (400-600 ms on a few seeds with long ascents). Every
analysis is a per-cell GDScript loop over the world; going below about 2 s needs either an
incremental re-analysis of only the cells joins changed, or the per-cell work in a native
step.

## Pictures

`tools/worldmap.gd`, saved outside the repo in `/tmp/claude-1000/godspark-passability/`:
- `map_dev3_before.png`, `map_dev3_after.png`: dev seed 3, whole world.
- `crop_dev3_before.png`, `crop_dev3_after.png` (and `_3x` enlargements): caves band,
  x 300-700, y 400-640, 1:1.
The caves still read as caves. The thin vertical lines (shafts with ropes and ladders) are
about 15% fewer by count but not clearly fewer to the eye. The ascent route is a clean walk
(orange); this seed's portal route is still rough (red).

## Open

- Joins are not clearly fewer on the map (rope + ladder 520 -> 441 per dev world). Slopes
  instead of shafts lost point-to-point share; the next step is joins that serve several
  pockets by design (one switchback stair or one long rope per pit) and grading the second
  look's joins against the nav graph so fewer get rebuilt.
- Generation is slower than before (2.5 s dev, 8.6 s small), not faster; see above.
- Large climbers 33% (target 43%): they follow 89% of what they plan; most misses are pairs
  the planner finds no way for, because joins are Medium-sized (two-wide shafts, five-high
  ways). Not done: Large-sized joins where the cave allows, or size marks on joins.
- Rough deep routes: 5 of 80 on dev (the portal's or ascent's in worlds where grading found
  no way along the line).
- Passer and the nav graph still disagree on a few moves per world (a corner landing, a rope
  under a plank); the stage's guarantee is checked by `tools/passability_sweep.gd`, not by the
  stage itself.
- `tools/cave_nav.gd mode=sites` walks long paths with world-sized replans (slow: 5 min for 10
  dev seeds).

## API and contract changes

- Worldgen stage order: `... routes, places, roads, passages, dressing` (`passages` moved from
  after `ruins`; the temporary `reach` stage folded into it). Only newly generated worlds
  change.
- `meta.routes[i].rough` is now rare (grading failed), not the rule for ramps.
- `GenContext.ascent.path`, `GenContext.portal.path`: feet cells of each ramp (generation only).
- `stage_passages.gd`: `stats` (as before, plus `phases_ms`, `absorbed`, `sizes`),
  `reach_stats` (`rounds`, `missing`, `clean`), `targets(c)`, `NEAR`.
- NavFollow, MonsterNav and NavSearch public calls are unchanged; jump dictionaries gain
  `tx`, `ty`, `peak`, `ov`.
- New tools: `tools/nav_probe.gd` (follower failures), `tools/passability_sweep.gd` (joins,
  timings, reach stats, nav check of every target).
- No change in `core/entity` (movement feel untouched; trace hashes not affected), `core/life`,
  `core/sim`, `monster_brain.gd` or `game/`.

## Tests and smokes

`godot --headless -s res://tools/run_tests.gd`: 3468 checks, 5 failed, all five in
`test_life.gd` and among the six known Life failures ("they fight each other", the sixth,
now passes). `test_passages` checks every site and route end on foot (nav graph) on two
1024x512 worlds and dev seed 7, and few rough routes. Smokes: plain, `FIGHT=1
SPAWN=goblin-warrior:2`, `RULES=1`, `SPAWNS=1 WORLD="gen=dev seed=3" SEE=`: NET SMOKE PASS;
`ALL=1`: failed once on the known "no bot waited in bed for the other", passed on the rerun.
