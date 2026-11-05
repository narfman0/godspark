# Hardening: closing M1 ("Dig together")

Branch `ws/hardening`, cut from main at 38f5570. An integration and hardening pass after the
five M1 tracks and the art track merged: the gaps from `todo.md` in priority order. Nobody
has played the result with a keyboard yet (no display here): see "Not verified".

## What was done

| # | Item | Where |
|---|---|---|
| 1 | Host ticks on its own thread at a fixed 30 Hz | `net/net_session.gd`, `net/loopback_hub.gd`, `game/main.gd` |
| 2 | Sparse client world, paged light, META message | `core/world/tile_world.gd`, `core/world/light_engine.gd`, `core/host/client_world.gd`, `view/chunk_mesher.gd`, `view/world_view.gd`, `net/protocol.gd` |
| 3 | Predicted digs and places, rollback; smoothed corrections | `core/host/client_world.gd`, `game/view_presenter.gd` |
| 4 | World meta on clients; world clock; day and night | `core/world/world_clock.gd`, `core/host/world_host.gd`, `view/world_view.gd` |
| 5 | The host runs the WorldSim; chronicle to clients; log overlay | `core/host/world_host.gd`, `net/host_endpoint.gd`, `game/chronicle_overlay.gd` |
| 6 | Dressing objects placed by worldgen, owned and replicated by the host | `core/world/dressing.gd`, `core/world/chunk.gd`, `core/world/worldgen/stage_dressing.gd`, `data/dressing.json` |
| 7a | Dig times exact (no epsilon) | `core/world/tile_edit.gd` |
| 7b | Bodies spawned in solid tiles step out | `core/entity/tile_collision.gd` (`depenetrate`) |
| 7c | Fast diagonal fall lands on a ledge corner | `core/entity/tile_collision.gd` (`move`) |
| 7d | Light for new chunks spread over frames | `core/world/light_engine.gd` (`deferred`, `process`) |
| 7e | Controls and run commands in README | `README.md` |

New tests: `test_net_session`, `test_sparse_world`, `test_prediction`, `test_world_clock`,
`test_host_sim`, `test_dressing`; additions to `test_collision`, `test_tile_edit`. New tools:
`tools/mem_client.gd`, `tools/bench_light_scroll.gd`. `tools/net_smoke.sh` takes `WORLD=`.

## API as built

```gdscript
# NetSession (net)
session.threaded = true                     # default; false ticks in _process as before
session.host_call(func(h: WorldHost) -> void: ...)   # runs on the host thread before a tick
session.with_host(func() -> Variant: ...)   # main thread, holding the host lock
session.halt_host()                         # join the host thread (before saving)

# TileWorld (core): sparse worlds
TileWorld.new(w, h, seed, sparse := false)
world.sparse; world.sky_line: PackedInt32Array      # per column, from meta.surface
world.chunk_at(cx, cy) -> Chunk | null; has_chunk(cx, cy); is_loaded(x, y); loaded_count()
world.ensure_chunk(cx, cy) -> Chunk; unload_chunk(cx, cy) -> bool   # emits chunk_changed
world.light_fg(x, y); unloaded_is_sky(cx, cy); scan_surface() -> PackedInt32Array
signal objects_changed(cx, cy)

# LightEngine
light.page_count(); light.deferred; light.backlog(); light.process(budget_us, want: Rect2i) -> bool

# ClientWorld
cw.apply_meta(m); cw.apply_clock(ticks); cw.apply_chronicle(lines); cw.apply_objects(cx, cy, records)
cw.view_pos(); cw.view_offset; cw.pending_count(); cw.predicted; cw.rolled_back; cw.hours(); cw.chronicle
signal meta_arrived(meta); signal chronicle_lines(lines)
const PREDICT_TIMEOUT := 3.0, CORRECT_BLEND := 0.05, CORRECT_SNAP := 8.0

# WorldClock (core)
WorldClock.new(); clock.ticks; advance(n); sleep(hours); hours(); whole_hours(); day()
clock.hour_of_day(); clock.sun(); WorldClock.sun_at(hours); WorldClock.describe(hours)
const TICKS_PER_HOUR := 1500, START_HOUR := 8, MOON := 0.04, DAWN, DUSK
K.DAY_SECONDS := 1200

# WorldHost
host.clock; host.sleep(hours); host.clock_jumped
host.sim: WorldSim | null; host.sim_origin; host.chronicle_sent; host.sim_usec; host.sim_behind()
host.recent_chronicle(n); host.save_state(dir); host.load_state(dir)
const SIM_BUDGET_US := 2000, CHRONICLE_ON_JOIN := 5
Ev.CHRONICLE {lines}, Ev.OBJECTS {cx, cy}

# Dressing (core)
Dressing.id(name); name_of(id); def(id); footprint(id); is_ceiling(id); count()
Dressing.records_in(world, cx, cy) -> [{id, x, y, v}]
Dressing.holds(world, id, x, y) -> bool
Dressing.on_tile_changed(world, x, y) -> Array[Vector2i]   # removes, returns changed chunks
# Chunk
chunk.objects (5 B per record: u16 id, u8 lx, u8 ly, u8 variant); object_count(); object_at(i)
chunk.add_object(id, lx, ly, v); remove_object(i)

# TileCollision
TileCollision.depenetrate(world, body, radius := 12) -> bool
```

## Protocol (version 1 -> 5)

| Type | Name | Layout | When |
|---|---|---|---|
| 28 | META | u32 raw size, zstd(var_to_bytes({surface: column deltas, biomes, bands, sites})) | once, after WELCOME, before any chunk |
| 29 | CLOCK | s64 WorldClock ticks | after META, every 10 s, at once after a jump |
| 30 | CHRONICLE | u8 n, n x (u16 len, UTF-8 <= 400 B) | new history lines; the last 5 on join |
| 31 | OBJECTS | s16 cx, s16 cy, u16 n, 5n B | a held chunk's whole object list after a change |

A CHUNK blob with objects starts with 0xD0 and a u16 record count, then zstd(tiles +
records); a blob without objects is the old format (old saves load unchanged). Routes are
not in META (the client does not need them yet). Each message has encode/decode and
malformed-input tests.

## How each item works

**1. Host thread.** `NetSession` starts a `Thread` on its first `_process`, after `main.gd`
has finished setting the host up. The loop sleeps (`OS.delay_usec`, at most 2 ms at a time)
until the next 1/30 s boundary and ticks; a stall over 4 ticks is dropped. Every tick runs
under `_host_lock`; queued `host_call`s run first. `LoopbackHub` locks every call, since the
listen server's own client (main thread) and the host (its thread) share it. `HostEndpoint`
signals fire on the host thread: `main.gd` connects `player_left` deferred. `main.gd` calls
`halt_host()` before reporting and saving. Debug: `frame_delay=MS` sleeps every frame,
`host_thread=0` restores render-loop ticking.

**2. Sparse world.** "Unloaded" is defined in `TileWorld`'s header. An unloaded cell's chunk
does not exist.
- `get_fg` reads it as bedrock (solid and unbreakable): the player cannot walk, dig or
  build into it. Writes to it are ignored.
- `light_fg` reads it as air above `sky_line` and bedrock at or below. `sky_line` is
  `meta.surface` from META; the test world, which has no meta, gets a scanned surface.
- The mesher treats an unloaded neighbour as open sky if the whole chunk is above the
  line, else as rock, and draws no mesh for an unloaded chunk.
- `content_hash` hashes it as an empty chunk; `ChunkHash` marks it so it never equals a
  held chunk.

`LightEngine` keeps one 2 KB page (block then sky) per computed chunk instead of two
world-sized fields. It frees pages of unloaded chunks with no loaded neighbour, skips
unloaded runs when scanning sky tops, and a chunk change widens the sun update only over
columns whose sky top moved. Hosts stay dense.

**3. Prediction.** Places are applied locally when the client-side check passes (the same
check that decides whether to send). Digs run a local `DigProgress`; at local completion the
tile turns to air. From then until that request's RESULT, the client sends neither
DIG_START nor DIG_STOP, so the host is never told to abandon a dig it has not finished.

Each predicted cell keeps `auth`, the host's value as last seen in the reliable, ordered
stream:
- FG deltas for a pending cell update `auth` and leave the shown tile alone.
- RESULT carries the host's tile after its own delta and settles the cell, shown as
  `auth` once no prediction is left on it.
- A 3 s timeout (lost link) or a fresh CHUNK for the cell falls back to `auth`.

So nothing applies twice, and the final state is always the host's. Corrections snap the
body; `view_offset` (old drawn position minus new) decays with a 0.05 s time constant, about
95% gone in 0.15 s; jumps over 8 tiles are not blended. The camera and the own actor use
`view_pos()`.

**4. Clock and day/night.** `WorldClock` counts host ticks (integer, no drift); a day is
`K.DAY_SECONDS` = 1200 s, a game hour 50 s. New worlds start at 08:00. The clock is saved in
`host.json` beside the world and replicated by CLOCK; clients advance it locally between
messages.

`LightEngine.sun = WorldClock.sun_at(hours)`: smoothstep dawn 05:00-07:00 and dusk
17:30-19:30, at most 2% change per game minute, and `MOON = 0.04` at night. Moonlight is two
numbers on purpose:
- For the rules, open ground at night is sky level 85 x 0.04 = 3, below DIM (5): SRD
  Darkness. SRD 5.2.1 puts the outdoors at night, even most moonlit nights, in Darkness.
- On screen, `WorldView` feeds the shader `max(sun, 0.25)` and blends the sky tint to blue,
  which is about 15% brightness after the shader's `pow(l, 1.35)`. That is enough to read
  terrain without a torch, so night is never black on the surface. Caves have no sky field
  and stay black.

**5. The living world.** A host whose world has sites builds `WorldSim.from_meta(meta,
seed)` at creation (0.7 ms on dev). The sim's hour 0 is the clock hour at creation
(`sim_origin`). Each tick steps it toward `clock.whole_hours() - sim_origin` one hour at a
time until 2 ms are spent (at least one hour).

New chronicle entries become CHRONICLE lines (`sim.describe`), and a joiner gets the last 5.
It is saved as `sim.bin`, zstd of `var_to_bytes({origin, sent, sim: sim.to_dict()})`; a
restored host steps on bit-identically (tested).

The windowed client shows lines in `ChronicleOverlay`: bottom left, at most 4 lines, each
fading after 12 s; C toggles it, and showing it again replays the last 4. Headless clients
print `[chronicle] ...`. `sleep=HOURS` at start and F6/F7 (+1 h, +1 day; host with a local
player) advance the clock; the sim catches up under its budget.

**6. Dressing.** `data/dressing.json` gained an append-only `ids` list (the u16 id table).
`cave_mushroom` and `stalagmite` may also stand on slate, the caverns' floor.

The `dressing` stage runs last, under its own RNG key, and changes no tiles:
- **Surface:** each column's top gets a try with chance 0.45, a weighted pick among
  objects allowed for that biome and top tile, and a footprint check (level support, open
  and unclaimed cells). Settlement grounds (site x ± size/2 + 4) only get 1x1 objects.
- **Caves:** one sample point per 700 tiles of the nadir-to-caves bands drops to a floor
  and places a cave object with chance 0.35.

Records are packed into their anchor chunk. They are saved, sent and hashed with the chunk.
The host runs `Dressing.on_tile_changed` whenever a tile changes between solid and not. It
removes objects whose support is gone or whose footprint holds a solid tile, then sends
OBJECTS to holders after the tile delta. `ViewPresenter` rebuilds its `DressingView` from the
held chunks at most every 0.3 s. Objects never block movement.

**7.**
- **(a) Dig times.** `TileEdit.dig_time` snaps float32 hardness to 0.1 ms, and
  `DigProgress` forgives 1e-6 s of accumulated error. Dirt is exactly 12 host ticks or 24
  controller steps. `WorldHost.DIG_EPS` is gone.
- **(b) Spawned in solid tiles.** `TileCollision.depenetrate` puts the feet on a whole
  row, moves x by whole tiles, and takes the smallest move (ties go up, then left) within
  12 tiles. `add_player` (spawn or rejoin record) and `add_monster` use it. A record inside
  rock now steps out next to where the player left, instead of jumping to the spawn.
- **(c) Corner snag.** In `TileCollision.move`, a falling body blocked sideways by a column
  whose top is within this step's fall (+0.05) above its feet is lifted onto it and
  continues. A taller column (a wall) still stops it.
- **(d) Light hitches.** `LightEngine.deferred` (turned on by `ViewPresenter`) queues
  whole-chunk changes. `process(budget, want)` computes cold chunks one at a time, nearest
  first, and applies each queued change once its neighbourhood is lit, until the budget is
  spent. `WorldView` gives it 3 ms per frame; a chunk not lit yet reads dark for a frame or
  two. Single-tile edits and carried lights stay immediate.

## Measured (this machine)

| What | Number |
|---|---|
| Bot join under CPU rendering, listen host slowed to 300 ms frames (`frame_delay=300`; Godot clamps delta to 133 ms) | WELCOME at 721 ms render-bound vs 68 ms threaded (headless baseline 48-75 ms). Over the same ~31 s the render-bound host ran 416 ticks (44% speed), the threaded one 964 (real time). Unslowed lavapipe here runs 110-175 fps, so the old 1.5 s did not reproduce without `frame_delay`. |
| Client memory, ClientWorld + 5x5 area + LightEngine with a 160x112 view lit (`tools/mem_client.gd`) | dev 14.7 MB -> 0.4 MB; large 471.4 MB -> 5.3 MB (343 MB tiles + 128 MB light before) |
| META size | 90 B on the test world; a 16384-column surface compresses under 8 KB (tested) |
| Sim cost | dev seed 3: 2.7 us per sim hour on average, worst hour 0.33 ms (one game hour = 1500 host ticks). Catching up a slept year: 12 ticks at <= 2.2 ms each (test), 9-17 ticks in game runs. Smoke host tick with a slept year: avg 170 us, max 2.3 ms; without: avg 88 us. |
| Worldgen time added by `dressing` | dev 19-20 ms of 638-658 ms total (seeds 1-3), small 40 ms of 1842 ms. About 950-1000 objects per dev world, 2150 on small, all holding. |
| Light, worst main-thread frame walking 13 t/s across dev seed 3 for 20 s (`tools/bench_light_scroll.gd`, arrivals plus the view's light rectangle) | synchronous: worst 151.9 ms, p99 77.9 ms; deferred (3 ms budget): worst 9.5 ms, p99 8.4 ms, mean 1.25 ms, backlog 0 at the end. The remaining 9 ms is one cold chunk's flood. |
| Smoke wall time | about 13 s (test world), about 16 s (dev world) |

"Before" for light is the current code with `deferred = false`. The original main code
refloods whole columns per chunk arrival, so it is no faster; it cannot run this bench
because it lacks the sparse world.

## Verification

- `godot --headless -s res://tools/run_tests.gd`: ALL PASS after every item (1291 checks at
  the start, 1451 at the end), with no script errors.
- `tools/net_smoke.sh` (test world): NET SMOKE PASS after every item.
- `WORLD="gen=dev seed=3" HOST_WAIT=3 tools/net_smoke.sh`: PASS. Bots dig and build on real
  terrain (the spawn settlement), hold 71 objects at join and 59-63 after their digs, and
  host and client digests (objects included) and positions match. Their clocks read Day 0
  08:02-08:13 against the host's 08:14 at exit.
- `WORLD="gen=dev seed=7 sleep=8640" ...`: PASS. Clock Day 360; the sim caught up a year in
  9 ticks; joiners got the chronicle lines. The bot script needed no change for
  generated ground: it already picks cells it can dig or place on.
- Screenshots (soft_godot, 1280x720, dev seed 3, art fetched), in
  `/tmp/claude-1000/godspark-hardening/`:
  - `final_day.png`: noon at the spawn settlement; grass, flowers and mushrooms; the Synty
    hero.
  - `final_night.png`: 22:00; moonlit grass, the torch glow, black underground.
  - `final_chronicle.png`: a slept year, with four chronicle lines in the overlay.

## Not verified

- **No human has played it.** Keyboard and mouse, F6/F7/C, the overlay toggle and the feel
  of predicted digs and correction blending are untested interactively. A second human
  client, NAT, real latency and loss are also untested.
- **Day shots show no trees.** Trees and bushes are kept off settlement grounds and are
  sparse on bumpy ground (about one tree per 80 columns). Trees exist in the world but no
  screenshot shows one.
- **Threaded host on Windows/macOS** and under heavy client load is not tested.

## Deviations from architecture.md

- META carries `surface` (as `sky_line`) and arrived with item 2, not 4: the sparse world
  needs it to light the surface under an unloaded sky.
- The world clock and sim are saved by `WorldHost.save_state` (`host.json`, `sim.bin`), not
  by `WorldSave`, so the worldgen save format is unchanged.
- Light pages replace the world-sized fields; `region_bytes` and the getters keep their API.
- `Dressing` and the dressing stage are new core files. Chunk blobs gained an optional
  object section.

## Known gaps (also in todo.md)

- One cold chunk still costs about 8 ms on the main thread (a worker flood with
  commit-on-main would remove it).
- Object removal is not predicted: a tree under a predicted dig vanishes one round trip
  later. Ceiling objects are never placed.
- The sim's calendar ("Year 2, spring") is its own; it is not tied to the clock's day count
  or season.
- Chronicle news is slow on small worlds: about 10 entries a game year on dev, and a game
  year is 120 real hours.
- The startup frame can take 130 ms while models load (GltfCache), unrelated to light.
- Rules darkness at night versus the visible moonlit picture is deliberate (see item 4).
  It will matter once darkvision and stealth rules land.
