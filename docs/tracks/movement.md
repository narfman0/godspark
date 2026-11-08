# Track C: bodies, platformer movement, tile interaction

Branch `ws/movement`. Pure simulation code in `core/`. It uses no nodes, no physics
server, no Input singleton and no global RNG. The same code runs a client's own player
and the host's monsters and validation.

## What was built

| File | What |
|---|---|
| `core/entity/body.gd` | `Body`: a box in tile units (pos = bottom centre), velocity, contacts, controller state |
| `core/entity/move_stats.gd` | `MoveStats`: SRD speeds plus size turned into platformer numbers from `data/movement.json` |
| `core/entity/player_input.gd` | `PlayerInput`: one step of intent; compact, lossless `to_bytes()` / `from_bytes()` |
| `core/entity/tile_collision.gd` | `TileCollision`: swept AABB vs the tile grid, contact queries, liquid fraction, DDA raycast |
| `core/entity/player_controller.gd` | `PlayerController.step()`: modes ground, ladder, swim, cling, fly |
| `core/world/tile_edit.gd` | `TileEdit`: dig and place rules, `TileEdit.DigProgress` |
| `data/movement.json` | every tunable: size table, run, jump, ladder, climb, swim, fly |
| `data/tiles.json` | tile 8 `platform` (one-way), tile 9 `ladder` |
| `core/world/tile_defs.gd` | additive: `TileDefs.platform`, `TileDefs.ladder` flag arrays (`solid` unchanged: blocks from every side) |
| `tests/test_collision.gd`, `test_player_controller.gd`, `test_tile_edit.gd` | 128 new checks (suite: 142, ALL PASS) |
| `tools/trace_run.gd` | ASCII picture of a scripted run: `godot --headless -s res://tools/trace_run.gd -- scenario=runjump` (jump, tap, runjump, pit, platforms, stairs, ladder, swim, spider) |

## API as built

```gdscript
# Body (RefCounted)
pos: Vector2, vel: Vector2, size: Vector2, facing: int   # -1 / +1
on_floor, on_ceiling, on_wall: bool; wall_dir: int       # -1, 0, +1
in_liquid: float                                         # 0..1, centre column
coyote, jump_buffer: float; jumping, climbing, clinging, flying, swimming: bool
drop_y: int (Body.NO_DROP); stepped: float               # stepped: tiles stepped up (+) or snapped down (-) this step, for view smoothing
Body.for_size("medium") -> Body; left(), right(), top(), center(), rect(), duplicate_body()

# MoveStats
MoveStats.from_srd({"walk": 30, "climb": 30, ...}, "large") -> MoveStats  # keys as in monster-forge's registry
MoveStats.player() -> MoveStats          # walk 30, medium
MoveStats.size_of("huge") -> Vector2; MoveStats.step_hz() -> int (60); stats.make_body() -> Body
fields: walk/climb/swim/fly/burrow (ft), hover, size_name, size, step_tiles, run_speed,
        jump_velocity, gravity, ... climb_speed (0 = can't), fly_speed (0 = can't), swim_speed

# PlayerInput
move_x (-1..1, quantized to 1/127 on write), jump, jump_pressed, up, down, dig, place, use,
target: Vector2i (s16 range), place_tile: int
to_bytes() -> PackedByteArray        # 2 bytes; 6 with a target; 8 with place
PlayerInput.from_bytes(b) -> PlayerInput   # null if truncated
equals(other) -> bool

# TileCollision
move(world, body, dt)                 # swept, axis-separated (x then y), refreshes contacts
update_contacts(world, body)
overlaps_solid(world, rect: Rect2) -> bool
ground_under(world, body) -> int      # tile id supporting the feet, -1 if airborne
on_platform_only(world, body) -> bool
raycast(world, from, to) -> {hit, tile, id, point, normal, distance}   # solid tiles only
liquid_fraction(world, body) -> float
free_below(world, body, max_dist) -> float
is_one_way(world, x, y), is_ladder(world, x, y), ladder_at(world, body, include_below := false), touching_wall(world, body, dir)

# PlayerController
PlayerController.step(world, body, input, stats, dt)   # call at 60 Hz, dt = 1/60

# TileEdit
TileEdit.REACH = 4.0
in_reach(body, x, y), can_dig(world, body, x, y), dig_time(tile_id, tool_power := 1.0),
can_place(world, body, x, y, tile_id, bodies: Array)
TileEdit.DigProgress.new(): update(at: Vector2i, tile_id, dt, tool_power := 1.0) -> bool (true on completion), fraction(), reset()
```

### Collision model
- The box moves along x, then along y. On each axis the leading edge steps column by column
  (or row by row) over every cell the box spans on the other axis, and stops at the first
  blocking cell. Speed does not matter: a 10000 tiles/s move stops on a 1-tile wall (tested).
  Bodies of any size work, including 7-tile-wide Gargantuans.
- A stopped edge is placed exactly on the tile boundary, and box sizes are multiples of
  1/8. So resting positions are exact in float32: no sinking, no jitter (600-step rest test,
  bit-exact).
- Contacts are probed within `EPS = 1e-3`. Cells the box already overlaps are not swept, so
  a body overlapping a solid can still move out.
- One-way tiles (`platform`, and a ladder's top rung) block only downward sweeps. These only
  test rows wholly below the feet, so "from above" comes for free. They are ignored while
  `climbing` and at or above `drop_y`.

### Controller
Each step: refresh contacts and liquid, update the coyote and buffer timers, pick a mode, set
the velocity, then move.
- **ground**: approach `move_x * run_speed` with ground accel / friction / turn accel, or air
  accel / air friction. Gravity is 1.25x while falling, with a terminal velocity. A jump
  fires when the buffer and the coyote time overlap. Releasing jump while rising multiplies
  vy by 0.45. Down + jump while standing only on one-way tiles drops through.
  - Step-up: blocked while on the floor, the body is lifted 1..`step_tiles` whole tiles if the
    swept box at that height is clear. That check includes headroom, so a body never steps
    into a ceiling.
  - Step-down: walking off a drop of up to `step_tiles` snaps down instead of falling.
- **ladder**: grabbed with up (overlapping a ladder in the centre column) or down (also from
  a ladder top). Speed is ±`ladder_speed` with no gravity. Jump lets go with a full jump (or
  just lets go with down held). Climbing past the top lands you on the top rung.
- **swim**: when `in_liquid >= 0.5`. Passive: weak gravity (20) against buoyancy (17 x
  submerged fraction), with drag. Up or jump held swims up at `swim_speed`; down swims
  down. A jump press is a stroke, or a leap (0.75 jump) if the head is out
  (`in_liquid < 0.85`). A dive is braked to swim speed at 150 t/s².
- **cling** (only with an SRD climb speed): push into a wall to walk up it at `climb_speed`.
  Down descends, no input hangs, pushing away lets go, and jump kicks off.
- **fly** (only with a fly speed): no gravity. Velocity approaches the input direction x
  `fly_speed`. Airborne, or up/jump held, means flying; on the ground with no up it walks.
  Down lands it.
- **burrow**: stub. `MoveStats.burrow_speed` is computed, but burrowers move as walkers.

## Tunables and why (data/movement.json, 60 Hz)

**Superseded in part on 2026-11-08 (docs/tracks/pace.md):** every speed below is now a share of
one pace, `pace.tiles_per_s_per_30ft` (4 tiles/s, not 13), and every acceleration a time to reach
it (the same times as these: top speed in 0.118 s and so on). At pace 13 the numbers below come
back (tests/test_pace.gd). Ladders are 0.75 of the pace (3 tiles/s), not 0.54. Jumps are unchanged;
a full running jump now carries about 3.3 tiles, not 9.75.

| Tunable | Value | Why |
|---|---|---|
| step rate | 60 Hz | Platformer feel needs 60. The host ticks at `K.TICK_HZ` = 30, so it runs 2 controller steps per tick. |
| run speed at walk 30 | 13 tiles/s (32.5 ft/s) | Terraria's top run is ~11-15 tiles/s. It scales linearly: walk 40 gives 17.3, walk 10 gives 4.3. |
| ground accel / friction / turn | 110 / 140 / 220 t/s² | Top speed in ~0.12 s (7 steps), a stop in ~0.1 s: snappy, with a little weight |
| air accel / air friction | 55 / 12 t/s² | Real air control, but momentum carries |
| jump | analytic 6.75 tiles, 0.40 s to apex: g = 84.4, v0 = 33.75 | Measured peak 6.47 tiles (the 60 Hz discrete loss is about 0.28). Feet clear 6 tiles, so a 6-high wall or the 6-wide test pit is easy. |
| fall gravity | x1.25 | Snappier descent. Measured full running jump: 9.75 tiles over 45 steps (0.75 s). |
| release cut | 0.45 | Tap: 1.6 tiles. Release after 8 steps: in between. Held: 6.47. |
| terminal fall | 40 t/s | Near Terraria's ~37 t/s. Sweeps make any speed safe. |
| coyote / buffer | 0.10 s / 0.12 s | The fire windows work out to 5 steps after leaving a ledge and 6 steps before landing (both tested) |
| ladder | 7 t/s up/down, 4 t/s sideways | About half the run speed. A climb speed raises it. |
| wall climb | 8 t/s per 30 ft of climb speed | Spiders (climb 30) scale walls at about 60% of their run |
| swim | 10 t/s per 30 ft; no swim speed = half walk = 5 t/s | SRD: swimming without a swim speed costs double |
| fly | 13 t/s per 30 ft, accel 60 | Same scale as running |
| sizes (w x h tiles) | tiny 0.75x0.75, small 1x1.75, medium 1.5x2.5, large 2.5x3.5, huge 4.5x5, gargantuan 7x7 | Medium matches the contract and fits a 2-wide, 3-high gap; Large fits neither (tested both). Step-up is 1 tile, Huge 2, Gargantuan 3. |
| `TileEdit.REACH` | 4 tiles (10 ft) from the box edge | A Medium reaches about 5 tiles from its middle: Terraria's building reach. SRD melee reach (2 tiles) would make building fiddly. Measured from the box, so big creatures reach further. |

Measured cost (this machine, one run): 7.8 µs per controller step for Medium, 11.1 µs for
Gargantuan, 20.8 µs for a 190-tile raycast.

## Deviations from docs/architecture.md
- `Body` has more fields than the contract lists (controller state, `wall_dir`, `drop_y`,
  `stepped`), plus `Body.for_size()` and `duplicate_body()`.
- `PlayerInput.move_x` is quantized to 1/127 on write. That is what makes the byte round
  trip lossless. Targets are s16, and `place_tile` is a u16.
- `TileCollision` exposes more helpers than `move`. `raycast` returns a Dictionary, and only
  solid tiles block it.
- A ladder's top rung (a ladder with no ladder above) is standable like a platform. This is
  not in the contract.
- `can_place` only refuses overlapping bodies for solid tiles. A platform, ladder or torch
  may go where someone stands. "Adjacent to a solid tile" is read as "a non-air
  foreground neighbour (4-way) or a background wall in the cell".
- Tile ids: 8 `platform`, 9 `ladder`. 10-15 are still free in the movement range. Id 7 is
  unused.
- `docs/architecture.md` itself was not edited (not in this track's ownership). The Track C
  block could gain `TileEdit.DigProgress`, `TileCollision.raycast` and the ladder-top rule.

## Known weaknesses
- x-then-y order: a fast diagonal fall whose feet are just below a ledge top hits the side
  and slides down instead of landing (the usual corner snag). Step-up only covers it when
  the body is grounded.
- `pos` is a float32 `Vector2`. Near x = 16384 one ulp is ~0.002 tiles, so very slow speeds
  lose precision far out. Contact positions stay exact. Determinism is verified on one
  machine only (same inputs, bit-identical over 900 steps). Cross-CPU determinism is
  untested.
- `in_liquid` samples the centre column only, so wide bodies half over water read oddly.
  Holding jump at the surface bobs around the 0.5 threshold, Terraria-style.
- No depenetration: a body spawned inside solid stays overlapping until it moves out.
- Climbers cling to walls only: no ceiling walking, no wall jump for players. `hover` is
  read but unused.
- Burrow is a stub.
- Huge and Gargantuan step-up (2 and 3 tiles) is implemented but only Medium step-up is
  tested. A Gargantuan resting on a bump is tested.
- A raycast exactly through the shared corner of two diagonal solids passes between them.
- No host-side validation API yet. Track D can re-simulate client inputs, since
  `step` is deterministic.

## Next steps
- Burrow: dig the tiles ahead at `burrow_speed`, through `TileEdit` and `world.set_fg`.
- A host validator: re-run `step` on received inputs, and accept the client position within
  a tolerance.
- Ceiling crawling for climbers, and a `Pathfinder` that reads the same MoveStats.
- Per-creature box overrides from the looks table (a horse is wider than tall).
