# Track: pace (the whole game slower, toward SRD real time)

Branch `ws/pace`, 2026-11-08. The ask: slow the whole game's pace, player and monsters together,
toward SRD real time (30 ft per 6 s round = 5 ft/s = 2 tiles/s), as one obvious tunable; find the
number that plays well and report honestly if the literal 2.0 does not; then make forge and Synty
walk and run playback match the new speeds.

## Summary

- **One knob:** `data/movement.json` `pace.tiles_per_s_per_30ft`, read by `MoveStats.pace()`.
  Every movement speed is a share of it and every acceleration a time to reach it.
- **Default 4.0** (it was 13.0). That is the SRD Dash in real time (60 ft a round), a 3 m/s jog.
  SRD real time is `2.0`, one edit away, but see "Why 4" first: below 4 the worlds stop being
  walkable without a worldgen change.
- **Jumps do not scale** (6.75 tiles high, 0.40 s to apex), so they clear the same obstacles. A
  running jump now carries 3.3 tiles, not 9.75.
- **Animation:** Synty clip speeds are now measured (the run was assumed 2x too fast). Walk, run
  and sprint are picked by the playback nearest 1x. The 15 forge kinds with a run clip use it (it
  was never played). The forge clamp is 0.5-3x.
  - The Synty player is planted at every speed: foot drift 0.02 m/s at a run (it was 1.5).
  - Forge bodies keep their feet while wandering (82 of 225 kinds, 15 at the old pace), but most
    still slide in a chase: they have only a walk clip, and it is slow.
- Suite and gate: see "Gate" at the end.

## Why 4 and not the literal 2 (measured)

All measured with the real controller, planner and follower (`tools/crossing.gd pace=X`; the
world is identical at every pace).

**Medium seed 1** (8192 tiles), the surface crossing on foot, digs=0:

| pace (tiles/s per 30 ft) | crossing | spawn to nearest town (212 tiles) | to the other neighbour (390) | longest town-to-town walk (1843 tiles) | result |
|---|---|---|---|---|---|
| 13 (old) | 11.1 min | 17.9 s | 31.1 s | 2.5 min | PASS |
| **4** | **39.5 min** | **63.7 s** | **128 s** | **8.4 min** | **PASS** |
| 3 | 48.4 min | 77.5 s | 137 s | 10.6 min | PASS |
| 2 (SRD) | 68.4 min | 106 s | 196 s | 15.3 min | PASS |

**Dev seed 1** (2048 tiles):

| pace | crossing | spawn to nearest town (183 tiles) |
|---|---|---|
| 13 | 2.8 min, PASS | 14.5 s |
| **4** | **10.0 min, PASS** | **46.8 s** |
| 2 | **FAIL**: "no ground gained" at x 1981 after 16.5 min | 91.5 s |

The deciding number is the running jump. Worldgen's passages stage
(`core/world/worldgen/stage_passages.gd`) joins standing spots across gaps of up to
`JUMP_ACROSS - 1` = 3 open columns under `ACROSS_ROOM` = 2 rows of headroom, landing a row up,
level or a row down.

Widest gap a Medium body clears (open columns), by pace (`tests/test_pace.gd`, and a probe):

| pace | open sky | 3 rows over the box | 2 rows | 1 row |
|---|---|---|---|---|
| 2 | 3 | 2 | **2** | 2 |
| 3 | 4 | 3 | **2** | 2 |
| **4** | 5 | 3 | **3** | 2 |
| 6 | 6 | 4 | 4 | 3 |
| 13 | 11 | 8 | 7 | 6 |

- Pace 4 is the slowest pace at which the worlds the generator makes are still walkable as made.
  - `tools/passability_sweep.gd` at pace 4, dev seeds 1-3: 131 of 131 targets reached on foot.
  - Dev seed 2's descent to the nadir and back passes (21.6 min on screen).
- Pace 3 or 2 needs `JUMP_ACROSS = 3`. That means more bridges and ways built by worldgen, every
  world's tiles change, and the golden hashes move. That is a worldgen change for the user to call.
  - `test_pace` fails loudly if the pace is set below what the stage counts on, and says so.
- The rest reads as "roughly SRD":
  - At 4 a walk-30 body runs 20 ft per 2 s game round (`K.ROUND_SECONDS` = 2). The SRD's own
    ratio of a move to an attack in one round would be 6.
  - At 2 a walk-30 body covers 10 ft per game round while attacking every 2 s: melee monsters
    could barely close on a target.
- **Is 4 playable?** It is slow next to before (3.5x the old crossing time) but not a crawl: the
  first town is a minute away, and walks between neighbouring towns take 1-2 min.
  - The 1843-tile gap on medium seed 1 is 8.4 min of walking. There is no fast travel in the game
    yet; that is the first thing to watch in play.
  - At 2, the same gap is 15 min and the first town nearly 2 min away.

### A 30 ft chase (`tools/chase_probe.gd`, real brains and combat on a flat world)

| monster | pace 13 | pace 4 | pace 2 |
|---|---|---|---|
| goblin-warrior (30 ft): from 20 tiles to its first swing | 1.4 s | 4.3 s | 8.5 s |
| wolf (40 ft): from 20 tiles to its first swing | 1.1 s | 3.2 s | 6.3 s |
| zombie (20 ft): from 20 tiles to its first swing | 2.0 s | 6.3 s | 12.5 s |
| wolf after a walk-30 player fleeing from 6 tiles: first swing | 0.9 s | 2.2 s | 4.0 s |
| goblin after a fleeing walk-30 player | never catches | never catches (gap holds at about 5 tiles) | never |

## What scales and what does not

| Thing | Now | Note |
|---|---|---|
| run, per 30 ft of walk | `pace` x 1.0 = **4 tiles/s** | was 13 |
| accelerations | the same times: top speed 0.118 s, stop 0.093 s, turn 0.059 s, air 0.236 / 1.083 s | at pace 4: 33.9 / 43 / 67.8 / 16.9 / 3.7 t/s² |
| ladder, rope | 0.75 x pace = **3 tiles/s** up/down; sideways 0.4 x pace = 1.6 | was 7 and 4 (0.54 and 0.31 of the run). A 30-tile rope takes 10 s |
| wall climb | 0.6 x pace per 30 ft of climb | spider 2.4 tiles/s (was 8) |
| swim | 0.75 x pace per 30 ft of swim; no swim speed: half the walk | 1.5 tiles/s without a swim speed (was 5) |
| fly | 1.0 x pace per 30 ft | |
| burrow | 1.0 x pace per 30 ft | the dig rate follows (`Burrow`, `MonsterBrain._dig_rate`, floored as before) |
| Gecko spark | `climb_mult` 0.25 / 0.4 / 0.55 x pace | was 3 / 5 / 7 tiles/s absolute |
| jumps, falls, gravity, coyote, buffer | unchanged | 6.75 tiles, 0.40 s to apex, terminal 20 |
| Dash spark (26-32 tiles/s for 0.15 s), roll (2 tiles in 0.4 s) | unchanged | tied to dodging and melee reach, not to travel. See open issues |
| projectiles, swing wind-ups, hit-stop, telegraphs | unchanged | times and tiles, not pace |
| monster brain distances (sight 30, keep bands, leash 48) | unchanged | tiles. Times (flee 6 s, give up 8 s) now cover a third of the ground |
| host speed check (`WorldHost._check_move`) | relative | `SPEED_MULT` x the body's own speeds, so it follows the pace |
| sim parties on screen (`WorldSim.TRAVEL_TPS`) | unchanged: wagons 1.5, on foot 2.5 tiles/s | now a walking pace beside bodies. `travel_tps()` caps them at 0.75 x pace (3.0 at pace 4: no change), so a lower pace never leaves a party's people behind its point |
| toll grace (`cultures.json` toll.grace_s) | **60 s** (was 20) | the time to find a guard, about the old distance |

## API as built

```gdscript
MoveStats.pace() -> float              # data/movement.json pace.tiles_per_s_per_30ft (or the override)
MoveStats.pace_override := 0.0         # measuring tools only (crossing.gd / trace_run.gd / gait_*.gd pace=X)
Sparks.climb_of(move: Dictionary) -> float   # Gecko: climb_mult x pace, or an absolute climb_speed
WorldSim.travel_tps(kind) -> float     # TRAVEL_TPS capped at TRAVEL_PACE_CAP (0.75) x pace
WorldSim.TRAVEL_PACE_CAP := 0.75
NavFollow.LADDER_TOL := 5e-4; NavFollow.STEP_OFF_LIFT := 0.45
LifeBrain.HURRY_TILES := 6.0
ActorBody.WALK_MPS 1.2, RUN_MPS 1.8, SPRINT_MPS 6.0          # measured, 1.8 m Synty body
ActorBody.SYNTY_SPEED_MIN/MAX 0.5/2.0; FORGE_SPEED_MIN/MAX 0.5/3.0; GAIT_STICK 0.223; STAND_MPS 0.1
ActorBody.synty_gait(mps, held := "") -> [clip, playback]   # static
ActorBody.forge_gaits() -> {clip: m/s}; forge_natural(v_tiles) -> float
ForgeMonster.play("run"|"sprint") plays "run" when the kind has it; ground_speed(c) reads
  clips.json ground_speed_mps first, else forward kinematics (a clip without feet uses the walk's)
CrossingBot result: reached (Array: seconds the walker first stood in each column)
```

`data/movement.json`:
- `pace {tiles_per_s_per_30ft, srd_real_time}`
- `run {speed, accel_s, friction_s, turn_s, air_accel_s, air_friction_s}`
- `ladder {speed, side_speed}` (x pace)
- `climb {speed, jump_off_mult}`
- `swim {speed, accel_s, ...}`
- `fly {speed, accel_s}`
- `burrow {speed}`

The old `tiles_per_s_per_30ft` and absolute accelerations per section are gone.

Tools:
- `tools/crossing.gd pace=X`: prints town-to-town walking times with the spawn marked.
- `tools/trace_run.gd pace=X`
- `tools/chase_probe.gd`
- `tools/gait_probe.gd` (every forge kind's gaits against the game's speeds; PACEGAIT summary)
- `tools/gait_strip.gd`: frames or overlaid frames from a fixed camera over a ground ruler, plus
  the measured drift of the foot on the ground. `sweep=1` finds a clip's real ground speed.

## Behaviour changes the slower pace needed (all found by tests failing)

- **Swimming out at a bank:** holding jump while pushing into a bank with the head out now leaps
  out, as a jump press does. At 1.5 tiles/s a swimmer no longer rose fast enough to pop over the
  lip, and bobbed at the surface forever (`test_deep_hazards`).
- **Ladders:** up no longer grabs a ladder while the body is rising in the air. A jump off a rope
  with W held used to re-grab it at once, because the centre stays in the rope column longer at
  4 tiles/s (`test_rope`).
- **NavFollow ladder arrival:** this was a latent bug.
  - A climb counted as at its node 0.02 short of the row, so it could stop 0.001 under a top rung,
    held by the rock beside it. That hit 4 of 24 cave paths and the tavern upper floors.
  - Now only float noise is forgiven.
  - A climb that steps off sideways next goes 0.45 tile past the row first; let go at the row, a
    body at walking pace dropped into the hole between ladder and ledge (dev seed 2's descent).
- **Stalled ambushes:** a real-time ambush with no blows for `stall_s` (45 s), where neither side
  broke, is now won by the side holding more of its strength. At equal speeds a fleeing escort is
  never caught, and the parties were held forever (`test_raids_below`).
- **Civilians hurry:** a calm civilian more than 6 tiles from its post walks at the full pace
  instead of 0.45 of it, since a party on foot moves its post at 2.5 tiles/s.

## Test assumptions that moved (and why)

| Test | Before | Now | Why |
|---|---|---|---|
| test_player_controller | walks of fixed step counts sized for 13 tiles/s; "runs at 13"; a running jump carries 8-12 tiles | step counts from `steps(tiles, speed)`; runs at the pace; the jump carries 0.7-0.9 s of the run | speeds are the pace |
| test_collision, test_rope, test_sparks | step counts for 13 / ladder 7 / Gecko 5 tiles/s | sized by the run, ladder and climb speeds; Gecko II = 0.4 x pace; Featherfall walks 60 steps off its ledge | same |
| test_monster_nav | a recorded jump crosses 7 columns; a 5-wide gap | crosses `stage_passages.JUMP_ACROSS` (4); a 3-wide gap (what the stage jumps) | the run is a third as fast |
| test_client_world | 30 steps ran 6.5 tiles | steps for 6 tiles at the pace | same |
| test_combat | the brain's first swing within 2 s of 12 tiles | waits up to 4 s more | same |
| test_combat_net | the 50 ms copy trails by > 0.5 tiles | by > 40 ms of the run (0.16 tiles) | the lag's distance scales with the run |
| test_dodge | a roll from a run keeps 13 tiles/s; run == 13 | keeps the faster of the run (4) and its own 5 tiles/s; run == pace | the roll is now faster than the run |
| test_world_host | a monster walks 5 tiles in 1 s | 0.75 s of its run | same |
| test_monster_brains | bruiser closes 15 tiles in 3 s; leash home of 50 tiles in 6.7 s; skittering > 13.5 | 5 s; 15 s; > 1.04 x pace | same |
| test_net_loopback | carl meets ann within 15 s | 160 tiles at the pace + 3 s | same |
| test_prediction | bob steps 0.2 s away | steps 2.6 tiles away | it was a distance, written as a time |
| test_raids_below | both players see the same raiders | each sees those its interest holds (in radius: seen; past radius + 1: not) | raiders string out along the road at a walking pace |
| test_m6_e2e, test_peoples_below | grace 20 s | 60 s (waits out the culture's own) | grace raised, see above |
| net smoke bot (`net/bot_client.gd`, every smoke) | the plain walk lasted 1 s (13 tiles) | it covers 12 tiles (at most 6 s) | after a 4-tile walk bot2 stood on a town street with nothing diggable near: `DEALS=1` failed 2 runs of 4, "dug only 1 of 4" |
| test_sim_world (budget) | — | `MoveStats.pace()` cached | `travel_tps` read the pace through the data dictionary on every party leg: the strategic day went 4.03-4.09 ms against its 4 ms budget; cached, under it again |

New tests: `tests/test_pace.gd` (25 checks), `tests/test_gaits.gd`.

## Animation (pictures looked at; numbers from tools/gait_strip.gd and tools/gait_probe.gd)

**Synty** (1.8 m player, the speeds measured where the foot on the ground stands still):
- walk 1.20 m/s at 1x (it was assumed 1.4)
- run 1.8 (assumed 3.6)
- sprint 6.0 (right)

| player at pace 4 | clip | foot on the ground moves |
|---|---|---|
| wander 1.2 m/s | walk x1.00 | 0.00 m/s |
| calm 1.35 m/s | walk x1.12 | 0.00 |
| run 3.0 m/s | run x1.67 (was run x0.83: +1.52 m/s, 51%) | 0.02 |
| sprint 6.0 m/s | sprint x1.00 | 0.00 |

Picture: `onion_player.png`, frames laid over each other from a fixed camera over a ruler. The run
and sprint show separate foot placements, not streaks.

**Forge**:

| | pace 13 | pace 4 | pace 2 |
|---|---|---|---|
| kinds measured | 225 | 225 | 209 |
| feet planted (0.5-3x) wandering / calm / chasing | 15 / 13 / 10 | **82 / 71 / 16** | 142 / 140 / 57 |
| playback a chase wants (median, p10-p90) | 24.9x (9.0-51.6) | 7.7x (2.8-15.9) | 3.8x (1.8-7.9) |

Where a run clip exists it carries the chase:
- bearded-devil runs at 0.71x
- ettin at 0.56x
- werewolf at 0.77x
- kobold-warrior at 2.07x (its walk is 0.28 m/s)

Pictures (`onion_mon1.png`):
- troll wander x0.9 / chase x2.3: feet planted (drift 0.04 / 0.10 m/s)
- werewolf wander walk x1.6 / chase run x0.8: planted (0.05 / 0.09)
- giant spider wander x3: planted (0.09). Chase x3: slides 1.89 m/s (63%): it has only a walk, at
  0.2-0.4 m/s

The pictures are on the dev machine under `~/.cache/pace/shots/`, not in git.

## Deviations

- Files outside the stated boundary were touched where the pace made them wrong:
  - `core/monsters/nav_follow.gd`, `core/life/life_road.gd`, `core/life/life_brain.gd`
  - `core/life/life_system.gd` (the grace default), `data/sim/cultures.json` (grace_s)
  - `core/sim/world_sim.gd` (`travel_tps`), `core/items/sparks.gd`, `data/sparks.json`
  - `game/ui/item_text.gd`, `game/ui/sheet_model.gd`
  - `data/life/people.json` (its doc line), `tests/crossing_bot.gd`, `net/bot_client.gd` (the
    smoke bot's walk)
- Not touched (the other track's): `data/looks.json`, `view/actors/looks.gd`, `view/fx/*`,
  `tests/test_looks.gd` (its forge playback checks hold unchanged).
- `core/world/worldgen/*` was not changed: no world changes at pace 4.

## Open issues

1. **Fast travel / long walks.** At pace 4 the medium crossing is 40 min. Some neighbouring towns
   are 8 min apart on foot. Nothing in the game shortens that yet (no mounts, no wagon rides, no
   fast travel). Watch it in play; this is what the slower pace costs.
2. **Jumps look tall for the run.**
   - 6.75 tiles high with a 3.3-tile reach: a pogo arc.
   - Lowering the jump means re-checking `stage_passages.JUMP_UP` (4 rows with a row to spare),
     `stage_cave_steps`, and every jump test.
   - A longer time to apex does not help the ceiling-capped jumps the stage counts on
     (measured: apex 0.5 s, same 3 columns).
3. **SRD-literal pace (2.0)** needs `stage_passages.JUMP_ACROSS = 3` (pace 3 too). That changes
   every generated world. `test_pace` names it.
4. **Forge chases slide.** Most forge kinds have only a walk, at 0.35x SRD speed. The fix is the
   forge's: run clips for walkers (forge-art plan step 3) and `ground_speed_mps` in clips.json.
   The game picks both up already.
5. **Giant spider ground speed:** forward kinematics says 0.21 m/s, the planted-foot sweep 0.40.
   Many-legged kinds are underestimated, so they play their walk too fast.
6. **The Synty wolf** (`looks.json keep_synty`) is a static mesh: its legs never move at any speed.
   The forge wolf walks. That is for the looks owner to decide.
7. **The roll (5 tiles/s) now beats the run (4).**
   - Roll spam averages about 4.4 tiles/s.
   - The Dash spark's 26-32 tiles/s bursts are now 6-8x the run (they were 2-2.5x).
   - Arrows (45 tiles/s) are 11x the run: you dodge them by rolling or jumping, not by running.
   - A monster's 0.5 s wind-up equals the time to walk out of a 2-tile reach.
8. **Stale processes.**
   - A `crossing.gd` run started early in this session against a sandbox-invisible `/tmp` path
     never exited, and a few `gait_strip.gd` runs hung on a script error before the fix. Each sits
     idle.
   - Killing them was refused by the session's permissions. They hold little memory; they can be
     stopped by hand (`pgrep -af "crossing.gd -- gen=medium seed=1 cache=/tmp"`, `pgrep -af gait_strip`).

## Gate

`E2E=test_m4_e2e,test_m5_e2e,test_m6_e2e tools/gate.sh` at f8882bc (the only uncommitted change
was this file):
- import exit 0
- suite: 10710 checks in 85 files, ALL PASS (162 s)
- all 8 net smokes PASS: plain, FIGHT, RULES, SPAWNS, ALL, LIFE, DEALS, WORLD_LIFE
- e2e unseeded x3 (m4, m5, m6): 264 checks, ALL PASS each (dice seeds 2583079153, 46968930,
  437707690)

An earlier gate run failed on two things, both fixed and recorded above:
- test_sim_world's 4 ms budget (4.03 ms)
- the DEALS smoke's bot2 dig (it fails at random)
