# Track: Traversal (M4 wave 1)

Branch `ws/traversal`, cut from main 82d7942. One commit per item. The direction (docs/m4.md):
a world you walk without digging; digging stays but gives plain rubble.

## 1. S drops through walkways

**Rule.** Standing only on one-way tiles (a walkway `platform`, stairs, a ladder's top rung;
nothing solid under any part of the feet), holding S (down) for `drop_hold` = 0.1 s (6
steps) drops the body through, with no jump. The hold counts only from a press made while
standing: S held on a ladder, in the air or in water disarms it (`Body.down_t = -1`) until S
is let go. So:
- brushing S (under 0.1 s) while walking along a walkway does nothing;
- climbing down a ladder that ends on a walkway with S held stops on the walkway (a climber
  is now held up by a walkway cell in its centre column, where the ladder ends; a ladder
  passing through a walkway has a ladder tile there, so it still passes), and landing on a
  walkway with S held stays there: press S again to go on down;
- one drop per press: after a drop S must be let go and pressed again for the next walkway;
- down + jump still drops on the first step, as before; S on solid ground does nothing;
- on a ladder or a ladder top S still climbs down (the ladder is grabbed first).

"Open space below" is read as "nothing solid under the feet": the body falls at least one
tile (onto stairs one tile below a walkway, for instance). Host-simulated bodies use the same
controller, so the same rule holds for monsters.

Tunable: `data/movement.json` `drop.hold` (`MoveStats.drop_hold`). New body state:
`Body.down_t` (copied by `duplicate_body`).

**Traces.** `tools/trace_run.gd` gained `hash=1` (a SHA-256 of every step's body state) and
two scenarios, `sdrop` (brush, hold through two walkways) and `ladderwalk` (down a ladder
onto a walkway, walk off, S). All twelve existing scenarios hash identically before and after
(none of them presses S on a walkway). Tests: `_s_drop` in `tests/test_player_controller.gd`.

## 2. Stairs and walkways that crisscross

**Tiles** (append-only; the traversal track holds ids 10-13): 10 `stairs_r` (rises to the
right), 11 `stairs_l` (rises to the left). Both are `platform` (one-way: passable from below
and from the side, standable from above) with `stairs` 1 or 2 (`TileDefs.stairs`). A
staircase is a diagonal line of treads, one tile up per tile across. Where a staircase
crosses a walkway, the crossing cell is a tread.

**Rules** (`PlayerController._stairs`, `_track_stairs`; new state `Body.on_stairs`):
- Moving on the floor, the column the box's leading edge enters is looked at. A tread at the
  feet's row there (the next one up) lifts the body one tile, at full run speed, if it holds
  **W** or is already **on a staircase**. Otherwise it runs straight through: running along
  the ground or a walkway past the foot of a staircase, or across one, never takes you up it.
- On a staircase, a tread one row below the floor in that column (the next one down) brings
  the body down onto it at once, even where a walkway continues level there: running down a
  staircase stays on it through the crossings.
- You are on a staircase once you arrive on a tread by a step up or down, a step-down snap or
  a landing; walking level onto a tread from a walkway does not count. Leaving the treads (or
  the floor) clears it.
- Branches: at the foot of a staircase that leaves a walkway or the ground, **W** takes it
  up, running on stays level. At the top of a staircase that leaves a walkway downward (the
  treads go on under the walkway), running on stays on the walkway and **S** drops onto the
  treads below (a landing on a tread puts you on the staircase; one tile of drop is enough).
  Where a walkway simply ends at a staircase's top tread you walk down it.
- **S** on a staircase: while moving it does not drop (you are walking the stairs); standing
  still, held 0.1 s, it drops through like a walkway.
- Headroom is checked as for step-up. Host bodies use the same code.
- `TileEdit.can_place`: a stair tread also holds on to a diagonal tread, so a staircase can
  be built up into the air.

**Drawing** (`view/chunk_mesher.gd`): a stair cell is a tread the full depth of the row, a
riser down its low side and a diagonal stringer at the back, mirrored for `stairs_l`.
Walkways are now planks with bearers (they were posts), ladders rails and rungs, ropes a
cord with a knot at the anchor. All lit like other blocks (KIND_BLOCK).

**Nav** (`core/monsters/nav*.gd`, additive): cell flag `STAIR` (64); edge `STAIRS` (8,
appended): to the next column one row up where a tread sits at the feet's row (the
follower holds W until on the staircase); a `PLATFORM` drop may be one tile when it lands on
a tread; a `DROP` follower on a walkway over its target presses S. Going down a staircase
is the existing one-row `DROP`. `MonsterNav.EDGE_NAMES` replaces the two name lists.

**Traces**: `stairsup` (W at the foot only; up through a crossing walkway to the top; back
down), `stairpass` (along a walkway across the stairs without W, then S onto the treads and
down). The twelve original scenarios still hash identically.

Tests: `_stairs` in `test_player_controller.gd` (13 checks), `_stair_tiles` in
`test_monster_nav.gd` (up, down, Small, a boxed walkway whose only way down is S onto stairs),
mesher shapes, diagonal stair placement.

## 3. Ropes

Tile 12 `rope` (`ladder` and `rope` flags: climbed like a ladder, W up, S down, jump off; not
solid, not opaque; hardness 0.1). Item `tile:rope` (every breakable tile is an item). Logic in
`core/world/rope.gd` (`Rope`); nothing but tiles is stored, so ropes save with the world and
reach every client as tile changes.

- **Aim**: at rock, a walkway or a stair, the rope is tied under it (the anchor is the open
  cell below); at an open cell, that cell is the anchor (`Rope.anchor_cell`, applied by the
  client before it asks).
- **Anchor** (`Rope.can_anchor`): air, and held by a solid or one-way tile above, left or
  right of it, or by a background wall in the cell; not directly under another rope (so each
  vertical run is one rope).
- **Unrolls** (`Rope.unroll`) down through air until the next cell is not air or it is
  `rope.length` = 30 tiles (`data/movement.json`).
- **Reeling in**: digging any rope cell, or using a rope item on a rope, removes all of it
  and gives one rope item back.
- **Falling**: when a solid or one-way tile next to (or above) a rope's top, or the wall
  behind it, goes, a top no longer held falls: the run is removed and one rope item drops at
  the anchor (`WorldHost._drop_loose_ropes`; guarded while a rope is being taken down).
- **Prediction**: only the anchor is predicted (the existing single-cell flow); the rest of
  the rope arrives as the host's TILE events. A reel is asked, not predicted. No protocol
  change.
- **Climbing**: on a rope with no sideways input, the body swings in under it, clear of the
  rock beside it (`PlayerController._ladder`, rope cells only; ladders unchanged), so a Medium
  body that grabbed a rope hung against a ledge from the ledge can climb down it.
- **Monsters**: rope cells carry the LADDER nav flag, so climbing paths use them.

Tests: `tests/test_rope.gd` (placement rules, length to a floor and to 30, run and top,
falling, climbing with the real controller, the host flow with items, two clients over the
loopback agreeing, a monster path down a rope, save and load).

## 4. A world you can walk without digging

Worldgen stage `passages` (`core/world/worldgen/stage_passages.gd`), inserted after `ruins`
(the last carving stage) and before `ores`, so it sees every cave, cavern, the deep road, the
ascent, the portal ramp and the buried ruins, and nothing in it depends on sites, places or
routes (all later). It only changes newly generated worlds; saved worlds keep their tiles.
`opts {"passages": false}` generates without it (the before numbers).

1. **Standing spots** for a Medium body (a 2 x 3 box: its left column and feet row), free of
   solid tiles, on a solid tile, a walkway, stairs or a ladder's top rung.
2. **Two-way moves** join spots (union-find): walking a column with a step of at most one row
   (headroom checked as the controller needs it); from the ends of floors, jumps up to 4 rows
   (rising straight, a row to spare) and across gaps of up to 4 columns (falls back are free);
   ladders and ropes join every spot along them. Only moves that work both ways count.
3. **Join**: the component under the first settlement flat (the spawn) is the network. Every
   other component of at least 4 spots is joined to the nearest network spot (cost |dx| +
   0.6 |dy|, searched in widening rings 24-400 tiles) with the cheapest believable feature:
   - steep (|dy| > |dx| + 2): a two-wide shaft with a ladder (surface and the deeps: roots and
     built ladders) or a hanging rope (caves) in its right-hand column (the column a body
     standing in it holds), a plank at its top; near the surface, landing planks where a
     hillside meets its open side, so nobody walks into it;
   - otherwise a way rising one row per column, then level, five rows clear: rock is cut,
     open air is bridged by walkway planks (level) or a flight of stairs (rising); in the
     deeps a rising rock floor gets stair treads (built stairs).
   Joins never cut bedrock or a paved floor (deep road, ramps; a buried ruin may be broken
   into), never touch settlement flats or settled caverns, and never cut a floor an earlier
   join laid. Joined parts become network. A second pass looks at the world as it now is and
   joins what an earlier join cut apart.
4. **Caverns**: each unsettled deep cavern gets a staircase from its floor to a walkway a
   third of the way up, a second staircase rising back across that walkway to a walkway two
   thirds up, and an old rope hanging from the upper walkway's end: branching ways up and
   down at two heights.

The spawn director keeps a pack's members by its spot when the spot's neighbour columns
drop down a shaft or spread into a player's view (`SpawnDirector._place_pack`): the new
shafts exposed that.

Nav (follower fixes that the new ways needed): a ladder edge steers to the node's middle (not
the ladder column's middle: a Medium body in a two-wide shaft would hit the rock), climbs to
the exact height of a step-off, presses down when a drop beside a ladder caught it, and a
jump waits at most 0.5 s to line up. Low jumps keep a late-steering arc too.

### Numbers

`tools/cave_nav.gd` (mode=pairs: real controller, NavFollow, 24 cave pairs ~40 tiles apart
per 1024x512 world; mode=sites: a nav-graph flood from the spawn settlement, whose jumps are
recorded from the real controller, to every site; walk=1 also walks each path with the real
body).

| | before | after |
|---|---|---|
| point-to-point, Medium, 10 seeds (3..31) | 114/240 (48%) | 171/240 (71%) |
| point-to-point, Large climber, 10 seeds | 103/240 (43%) | 66/240 (28%) |
| sites on foot from the spawn (graph), dev, 10 seeds | 63/160 (39%), all sites in 0 of 10 | 155/160 (97%), all sites in 7 of 10 |
| sites on foot (graph), small, 3 seeds | 30/81 (37%), 0 of 3 | 80/81 (99%), 2 of 3 |
| sites walked by the real body (NavFollow), dev, 3 seeds | - | 13/48 (27%) |
| generation time, dev (2048x1024) | ~0.79 s | ~2.1 s (+1.2-1.5 s; the stage ~1.2-1.5 s with its second pass) |
| generation time, small (4096x1536) | ~2.4 s | ~6.5 s |

Misses left (graph): a buried ruin, two portals in the nadir, one surface settlement and two
lairs over 10 dev seeds. Point-to-point misses are about half planner misses inside its
64-tile window (the join goes the long way round) and half the follower failing a jump. The
real-body long walks fail mostly on NavFollow's jump execution over thousands of nodes, not
on missing ways (the same paths exist in the graph). The Large climber lost ground: two-wide
shafts and five-high ways fit a Medium body, not a Large one.

Not met: point-to-point above 85% (71%), every site in every seed (97% of trips; 7 of 10
worlds complete). Feature counts per dev world: about 900 joins (300 ladders, 280 ropes,
the rest stairs, steps and bridges): dense; see the screenshots.

## 5. Rubble-only digging and supplies

- Tile 13 `rubble` (solid, opaque, hardness 0.5): what digging any terrain gives
  (`data/items/base.json` `tile_drops`: dirt, grass, stone, slate, cobblestone, wood and
  rubble give `tile:rubble`); placing it puts a rubble tile.
- Ore tiles give trade goods `ore:copper`, `ore:iron`, `ore:silver` (kind material, `trade`,
  a value, not placeable).
- Built things give themselves (walkways, stairs, ladders, ropes, torches, campfire, bed,
  shrine): every other breakable tile still gives `tile:<name>`.
- `tile:wood` and every other block item in old saves stays valid and placeable; nothing
  produces them any more (loot's `plant` materials give `supplies`).
- `supplies` (stack 999, value 1) replace wood in `data/items/recipes.json`: torch (1 -> 3),
  campfire (4), bed (6), ladder (1 -> 3), walkway (1 -> 3), stairs either way (1 -> 3), rope
  (3 -> 1).
- Starting kit (`ItemsSystem.give_kit`): hotbar 1 the attack slot (empty, selected), 2
  torches x10, 3 campfire, 4 two healing potions, 5 bed, 6 two ropes, 7 supplies x12. No
  blocks.
- Gear materials and the +3 budget are untouched.
- The smoke bots dig three tiles and place the rubble they get (`net/bot_client.gd`).
- Carpenter's Tools Knack deeds also count stair placing (`place:wood` kept for old deeds).
