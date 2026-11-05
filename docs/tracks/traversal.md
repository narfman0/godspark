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
