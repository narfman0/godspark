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
