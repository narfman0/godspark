# Track D: authoritative host loop, co-op networking, boot

Branch `ws/net`. Built against `TileWorld.make_test()`; Track B (view) is merged and wired
in through a presenter. Track A (WorldGen / WorldSave) is not in the tree yet: the seams for
it are `main.gd: world_source()` and `WorldHost.world_saver`.

## What was built

| File | What |
|---|---|
| `core/host/world_host.gd` | `WorldHost`: the authoritative loop. Owns the TileWorld and the entities, runs tile edits, checks client movement, seeds `Dice.rng`, and fills a per-tick outbox. Saves and loads players. |
| `core/host/host_entity.gd` | `HostEntity`: id, kind (PLAYER / MONSTER), owner peer, name, Body, MoveStats, look, `brain` (for monsters), dig state, validation state. Also the shared body flag bits. |
| `core/host/client_world.gd` | `ClientWorld`: the client mirror. Partial TileWorld, own player (60 Hz, freezes outside loaded chunks), remote entities with interpolation buffers, corrections, and edit requests. |
| `core/host/interest.gd` | `Interest`: the chunk of a position, Chebyshev distance, the chunks around a point (nearest first) and the chunks under a box |
| `core/host/chunk_hash.gd` | `ChunkHash.of(world, coords)`: SHA-256 over a set of chunks, to compare a client's partial world with the host's |
| `net/protocol.gd` | `Protocol`: every message's byte layout, encode and decode in one file, version handshake |
| `net/net_transport.gd` | `NetTransport`: the transport interface: `poll() -> [[kind, peer, bytes]]`, `send`, `disconnect_peer`, `close` |
| `net/enet_transport.gd` | `EnetTransport`: raw `ENetMultiplayerPeer` (no SceneMultiplayer, no RPC), 2-5 s peer timeouts |
| `net/loopback_hub.gd`, `loopback_transport.gd` | In-process queues with simulated latency and ordered, loss-free delivery. Used by tests and by the listen server's own player. |
| `net/multi_transport.gd` | Several server transports as one (ENet plus loopback for a listen server) |
| `net/host_endpoint.gd` | `HostEndpoint`: host side of the protocol. Handshake, interest areas, chunk streaming under a budget, deltas, snapshots, timeouts, traffic counters. |
| `net/client_endpoint.gd` | `ClientEndpoint`: client side. Handshake, message to ClientWorld calls, 60 Hz stepping, state and edits up, consistency check. |
| `net/net_session.gd` | `NetSession` (Node): owns transports and endpoints. Ticks the host at 30 Hz and the client every frame. |
| `net/bot_client.gd` | `BotClient` (Node): a scripted client that joins, walks, jumps, digs, places, checks, leaves, rejoins, checks again and says a final BYE |
| `game/main.gd`, `main.tscn` | Boot from the command line (below). Registered as the main scene. |
| `game/presenter.gd` | `Presenter`: the thin presentation interface (actor added/moved/removed, chunk arrived/dropped, tile changed, edit result, corrected, `tile_at_screen`) |
| `game/log_presenter.gd` | `LogPresenter`: for headless runs and bots; it logs |
| `game/view_presenter.gd` | `ViewPresenter`: `LightEngine` over the client's partial world, `WorldView`, `CameraRig` following the own player, and a carried torch on the own player |
| `game/local_input.gd` | `LocalInput`: fills `PlayerInput` from input actions; the target tile comes from `presenter.tile_at_screen(mouse)` |
| `project.godot` | `run/main_scene`, and an `[input]` section: move_left/right (A/D, arrows), move_up/down (W/S, arrows), jump (Space), dig (LMB), place (RMB), tile_1..4 (wood, platform, torch, ladder) |
| `tools/net_smoke.sh` | A headless dedicated host plus two headless bots over real sockets. Prints `NET SMOKE PASS`. |
| `tools/net_bench.gd` | Chunk sizes, 4-player tick cost and bandwidth, ENet join time |
| `tests/test_protocol.gd`, `test_world_host.gd`, `test_client_world.gd`, `test_net_loopback.gd`, `test_net_enet.gd`, `tests/net_rig.gd` (helper) | 270 new checks (suite: 426, ALL PASS) |

No changes to `TileWorld`, `Chunk`, `core/entity` or `core/world`. Everything is in new files.

## Boot

```
godot                                              host and play locally (listen server, port 24650)
godot -- host [port=N] [world=DIR] [name=X]        same, explicit
godot -- offline                                   single-player: host with no ENet port
godot --headless -- dedicated [port=N] [world=DIR] [expect=N]
godot -- join=ADDR[:PORT] [name=X]
godot --headless -- join=ADDR[:PORT] bot [name=X] [digs=N] [places=M] [dir=1|-1] [delay=S] [rejoin=0|1]
any:  timeout=S   size=WxH (test world, default 1024x256)   view=log   shot=PATH.png [shot_after=S]
```

Single-player, listen and dedicated all run the same host code. A listen server's own player
is a normal client: its `ClientEndpoint` talks to the `HostEndpoint` over a zero-latency
loopback link (peer id `NetSession.LOCAL_PEER`), next to the ENet peers. Headless processes
use `LogPresenter`; windowed ones use `ViewPresenter`. `world=DIR` (default
`user://worlds/dev`) is where players are loaded from at start and saved to at exit.

## Protocol (`net/protocol.gd`, version 1)

One message per packet. Byte 0 is the type. Everything is little-endian. `str` is a u8
length plus UTF-8, capped at 64 bytes. `vel` is two s16 at 1/64 tile/s. Messages marked U
are unreliable-ordered; all others are reliable-ordered on one channel. That ordering
matters: a chunk blob always arrives before the tile deltas for that chunk. `decode()`
returns `{}` for an unknown type, a truncated message, or trailing bytes. It is fuzzed with
300 random packets in the tests.

| Type | Name | Direction | Layout | Bytes |
|---|---|---|---|---|
| 1 | HELLO | C→H | u32 magic "GSPK", u16 version, str name | 8 + name |
| 2 | STATE (U) | C→H | u16 epoch, u32 seq (60 Hz steps), f32 x, f32 y, vel, u8 flags | 20 |
| 3 | EDIT | C→H | u32 req, u8 op (0 dig start, 1 dig stop, 2 place), s16 x, s16 y, u16 tile | 12 |
| 4 | BYE | C→H | u8 reason (LEAVING, FINAL) | 2 |
| 5 | CHECK_REQ | C→H | str tag | 2 + tag |
| 16 | WELCOME | H→C | u16 version, u32 your entity id, u32 width, u32 height, s64 seed, f32 x, f32 y, u16 epoch, u8 tick_hz, u8 snapshot_hz, u8 radius | 36 |
| 17 | REJECT | H→C | u8 reason (VERSION, FULL, NAME_TAKEN, BAD_NAME), str text | 3 + text |
| 18 | CHUNK | H→C | s16 cx, s16 cy, `Chunk.to_bytes()` blob (rest of packet) | 5 + blob |
| 19 | UNLOAD | H→C | u16 n, n × (s16 cx, s16 cy) | 3 + 4n |
| 20 | TILES | H→C | u16 n, n × (u16 x, u16 y, u8 layer, u16 value) | 3 + 7n |
| 21 | ENT_ADD | H→C | u32 id, u8 kind, f32 w, f32 h, f32 x, f32 y, u8 flags, str name | 24 + name |
| 22 | ENT_REMOVE | H→C | u32 id | 5 |
| 23 | SNAPSHOT (U) | H→C | u32 host tick, u8 n, n × (u32 id, f32 x, f32 y, vel, u8 flags) | 6 + 17n |
| 24 | CORRECT | H→C | u16 epoch, f32 x, f32 y, vel | 15 |
| 25 | RESULT | H→C | u32 req, u8 reason (`WorldHost.Reason`), s16 x, s16 y, u16 tile now | 12 |
| 26 | CHECK | H→C | str tag, u16 n, n × (s16 cx, s16 cy), 32 B SHA-256, f32 x, f32 y | 44 + tag + 4n |
| 27 | KICK | H→C | u8 reason (TIMEOUT, SHUTDOWN...), str text | 3 + text |

Flags byte (shared by STATE and SNAPSHOT): bit 0 facing right, 1 on floor, 2 climbing,
3 swimming, 4 flying, 5 clinging, 6 digging, 7 jumping. `HostEntity.state_name()` turns it
into a view state (idle, run, jump, fall, climb, swim, fly, cling, dig).

Handshake: on connect, the client sends HELLO. If the magic or version is wrong, the name is
empty or already playing, or the host has 4 players, the host answers REJECT and
disconnects. Otherwise it answers WELCOME and starts streaming. A peer that sends no HELLO
within 5 s gets KICK(TIMEOUT). ENet drops a silent peer after 2-5 s.

CHECK exists for tests. The host first flushes every pending tile event to that peer, then
hashes the chunks it believes the client holds and sends that list with the digest. The
client hashes the same list when CHECK arrives. Because the channel is reliable and ordered,
the client then holds exactly the state the host hashed, even while other players are
editing.

## Host loop (`HostEndpoint.tick`, 30 Hz)

1. Read packets. HELLO adds a player. STATE goes to `WorldHost.submit_state`. EDIT goes to
   `request_dig` / `stop_dig` / `request_place`. BYE or a disconnect removes the entity.
2. `WorldHost.tick()`: advance each held dig (re-checked every tick; it completes after
   `TileEdit.dig_time`). Step host-simulated entities (`brain.think` → `PlayerController.step`
   × 2). Player bodies are not stepped on the host.
3. Route the outbox:
   - TILE events go to every peer that holds the chunk, and drop the cached blob.
   - CORRECT and EDIT_RESULT go to their owner. Its pending deltas are flushed first, so the
     tile change arrives before its result.
   - LEAVE sends ENT_REMOVE to anyone who had the entity.
4. Interest, per playing peer, centred on the chunk under the host's copy of the player's
   centre:
   - Queue the chunks within `radius` (2, so 5×5 chunks = 160×160 tiles), nearest first.
   - Chunks past `radius + 1` are forgotten and sent as UNLOAD. The client drops chunks
     only when the host says so, so the two sets cannot disagree.
5. Stream queued chunks round-robin over peers: up to 16 chunks per peer per tick and
   96 KB per tick in total. Blobs are cached per chunk until the chunk changes.
6. Flush tile deltas, one TILES message per peer per tick.
7. Every 2nd tick (15 Hz), per peer:
   - Entities within `radius` chunks get ENT_ADD; past `radius + 1` they get ENT_REMOVE.
   - Then one SNAPSHOT of every visible entity except the peer's own.

`WorldHost` is fully drivable without networking: `add_player`, `submit_state`,
`request_dig`, `request_place`, `tick`, `drain`. Monsters slot in with
`add_monster(stats, pos, brain, look)`; a test monster walks with a trivial brain.
Entities live in one id-keyed, insertion-ordered dictionary, so iteration is deterministic.
`WorldHost` seeds `Dice.rng` from the world seed; the newest host owns it.

## Client model (`ClientWorld`)

- `TileWorld` of the host's dimensions. CHUNK messages decode into it and emit
  `chunk_changed`, which WorldView and LightEngine already handle. TILES messages go
  through the normal setters (`tile_changed`). UNLOAD clears a chunk and emits
  `chunk_changed` and `chunk_dropped`.
- Own player: `PlayerController.step` at 60 Hz, locally. If any chunk under the body's box,
  plus 3 tiles and one step of travel, has not arrived, the body is frozen. Unloaded chunks
  read as air, so the player would fall without this.
- It sends STATE every 2nd step (30 Hz), stamped with the correction epoch and the step
  counter.
- Edits:
  - Dig is held: DIG_START when it starts or retargets, DIG_STOP on release. A refused dig
    is asked for again while the button is held.
  - Place fires on press and again on retarget while held.
  - Requests that the local world already rules out are not sent.
  - Edits are not predicted: tiles change when the host's delta arrives, one round trip
    later.
- Correction: snap to the host's position, adopt its epoch, clear the controller's jump,
  climb and drop state. States from the old epoch that are still in flight are ignored by
  the host.
- Remote entities: each keeps a buffer of `[host time, pos, vel, flags]`. They are drawn
  0.1 s behind a host clock estimate. The clock advances locally and is pulled 10% toward
  each snapshot's tick; a jump of more than 0.5 s resyncs it.
  - Between samples: interpolation.
  - Past the newest sample: velocity extrapolation for at most 0.1 s.
  - Out-of-order and duplicate snapshots are dropped.
  - Snapshot entries for ids not added yet are ignored.

## Validation rules (`WorldHost.submit_state`)

- STALE (ignored, no correction): the epoch is not current, or seq is not newer than the
  last accepted one.
- Time allowed: the client's own step count since the last accepted state, capped at the
  host's real ticks since then plus 0.25 s. A client cannot buy distance by claiming more
  steps (tested).
- TOO_FAST: compare each axis of the move against speed × time + 1.5 + step_tiles, where:
  - horizontal speed is 1.25 × max(run, fly, swim, ladder-side);
  - up is 1.25 × max(jump velocity, fly, ladder, climb, swim);
  - down is 1.25 × max(terminal fall, fly).
- OUT_OF_BOUNDS: the box leaves the world, or the position is NaN or infinite.
- IN_SOLID: the box, shrunk by 0.05, overlaps a solid tile.
- On refusal: the body stays at the last accepted position with velocity zero, the epoch
  goes up, and CORRECT goes to the owner.

Edits are refused with a reason (`WorldHost.Reason`):

| Edit | Reasons |
|---|---|
| dig | OUT_OF_BOUNDS, NOTHING_THERE (air, or another player finished it first), UNBREAKABLE, OUT_OF_REACH (also when the digger walks away mid-dig) |
| place | BAD_TILE (air, undefined ids, unbreakable tiles like bedrock), OUT_OF_BOUNDS, OUT_OF_REACH, OCCUPIED, NO_ANCHOR, BLOCKED (a solid tile over any entity's box) |

All of these use Track C's `TileEdit` checks with the host's copy of the body.

## Measured (this machine)

| What | Number |
|---|---|
| Chunk blob, `make_test` world | 19-89 bytes, mean 25 |
| Chunk blob, noisy stand-in (noise caves, ore specks, walls, water) | min 19, median 192, mean 148, p95 279, max 337 bytes. Encode 4.3 µs per chunk. Real worldgen will differ; re-measure with `tools/net_bench.gd` when A lands. |
| Initial area (25 chunks), real ENet on localhost | welcome at 50-77 ms, all 25 chunks at 92-110 ms (smoke, test world); 100 ms (bench, noisy world, 2.7 KB of chunks) |
| Initial area, loopback with 50 ms one-way latency | 183 ms |
| Snapshots | 6 + 17 bytes per visible entity, 15 Hz: 255 B/s per visible remote. 855 B/s for a player seeing 3 others. Total host→client about 1 KB/s in the 4-player wander bench. |
| Client→host | 614 B/s per player (STATE 20 B at 30 Hz, plus edits) |
| Wire overhead | not measured. UDP/IP is 28 B per packet plus the ENet header (about 10-20 B), so about +600 B/s per direction at 15-30 packets/s. Measuring needs a packet capture. |
| Host tick, 4 players moving and digging (loopback, `HostEndpoint.tick` including `WorldHost.tick`) | mean 85 µs, median 90, p99 141, max 244 µs (budget at 30 Hz: 33 ms) |
| Host tick in the smoke run (2 bots, ENet) | mean 94-115 µs, max 0.8-1.1 ms (the max is a join: chunk encodes) |
| `tools/net_smoke.sh` wall time | about 13 s |

## Verification

- `godot --headless -s res://tools/run_tests.gd`: **426 checks, ALL PASS**, with no
  leak warnings at exit. The suite covers:
  - message round trips and malformed input;
  - host digs (timing, refusals, digging the same tile at once, walking away);
  - places (each refusal);
  - teleport, inside-rock, out-of-bounds and NaN corrections, and the seq/time cap;
  - interest: a far player's edits and entities are not sent, and arrive on approach, with
    UNLOADs behind;
  - late join after edits; full host; name taken; version mismatch; silent-peer timeout;
    abrupt drop and clean leave;
  - loopback (50 ms) with up to 4 clients ending with identical digests;
  - a real ENet host and client in one process (join, dig, check, leave).
- `tools/net_smoke.sh`: **NET SMOKE PASS** on 4 of 4 runs.
  - Setup: a dedicated host, then bot1 and bot2 (bot2 two seconds late, after bot1's edits).
    Each bot digs 3-4 tiles and places 3-4 blocks, checks, leaves, rejoins at the position
    it left (host-side record) and checks again.
  - Pass condition: the final host and client digests are equal and positions match within
    0.05 for both bots; every process exits 0; no strays.
  - It also prints per-message-type traffic and the bots' join times.
- Screenshot proof under `tools/soft_godot.sh`: a listen host (`ViewPresenter`) with a
  headless bot joined and digging. Both players and the bot's hole are visible. Saved
  outside the repo at
  `/tmp/claude-1000/-home-narfman0-workspace/7cf54a79-3f3e-43af-87e7-ba72c23eb7f8/scratchpad/coop.png`.
  Interactive play (keyboard, mouse picking, a second human) is not tested.

## Deviations from docs/architecture.md

- Track D was built before Track A landed, against `TileWorld.make_test()`.
- More classes than the contract names:
  - `ClientWorld`, `Interest`, `ChunkHash` and `HostEntity` in `core/host/`;
  - the transport classes, `HostEndpoint` and `ClientEndpoint` in `net/`. NetSession is a
    thin node over them.
- The protocol is not inside `NetSession`: endpoints talk to a `NetTransport`, so tests and
  the listen server's own player use the same code over loopback.
- Outbox events are Dictionaries with a `type` (`WorldHost.Ev`), not typed objects.
- Interest is a Chebyshev square of chunks (radius 2, with hysteresis to 3), not a circle.
  The client drops chunks only on the host's UNLOAD.
- Client states go up at 30 Hz, snapshots come down at 15 Hz. Positions are f32;
  velocities are 1/64 tile/s.
- Saving: `save_players(dir)` / `load_players(dir)` write `dir/players/<file-safe
  name>.json` (`{name, pos}`). `save(dir)` also calls the `world_saver` seam when it is set.
- `WorldHost` adds `DIG_EPS = 1e-6` to each tick's dig time. `TileDefs.hardness` is
  float32, so 0.4 reads as 0.40000001 and Track C's `1e-9` tolerance would cost one extra
  tick.
- The input actions and `run/main_scene` are in `project.godot`, next to Track B's
  `[shader_globals]`.

## Known weaknesses

- **Client memory.** The client's `TileWorld` allocates every chunk of the world, and Track
  B's `LightEngine` adds 2 bytes per tile. A large world (16384×4096) would cost about
  256 MB + 128 MB per client, and twice that on a listen server: the host's world plus the
  local player's mirror. This needs a sparse TileWorld (or a shared world for the local
  player) before large worlds.
- **Unloaded chunks read as air** on the client. The own player is frozen out of them, but
  LightEngine and WorldView treat them as open sky until they arrive. That is outside the
  camera at radius 2, but visible if someone zooms far out.
- **Validation is an envelope check.** At 30 Hz states, a cheater can still:
  - pass through a 1-tile wall between two states;
  - hover, since gravity is not enforced;
  - stand in a tile that someone just placed.

  Replaying inputs through the deterministic controller would close these; the inputs are
  not sent today (STATE carries positions only).
- **Corrections snap**, with no smoothing.
- **Edits are not predicted**: a dig or place shows one round trip after the host applies
  it.
- **Interest follows the host's copy of the player**, which lags by latency. A player
  running at 13 tiles/s needs over 3 s of lag to reach unloaded chunks. If that happens,
  they freeze rather than fall.
- **The listen server's tick is tied to render frames** (`_process`, at most 4 ticks per
  frame). Under CPU rendering (lavapipe), a bot's WELCOME took 1.5 s. A slow-rendering
  host slows the world for everyone. Ticking on a thread or a timer is the fix.
- **No bandwidth adaptation**: the chunk budget is fixed, and ENet's queue depth is not
  checked.
- **Snapshots are full state** (no delta compression or priority). That is fine for players.
  At 17 B per entity, 50 visible monsters would be 12.7 KB/s.
- **Identity is the name**. There is no authentication, and a rejoin restores the position
  by name.
- There is no inventory: placing is unlimited.
- Entity ids are u32 and never reused.
- `Dice.rng` is a global static, so there is one host per process (the newest wins).
- The world `meta` (biomes, sites, routes) is not sent to clients.
- Cross-machine play (NAT, real latency, packet loss) is untested. Everything ran on
  localhost.

## What "Dig together" still needs from the other tracks

- **Track A (worldgen, saves)**:
  - Replace `main.gd: world_source()` with `WorldSave.load(dir)`, falling back to
    `WorldGen.generate(...)`.
  - Set `host.world_saver = WorldSave.save`.
  - Have the WELCOME (or a new META message) carry `world.meta` if the view or clients need
    biomes and sites.
  - Re-measure chunk sizes and join time on generated terrain.
  - Spawn: `WorldHost.find_spawn` scans the middle column. A biome-aware spawn should come
    from `meta`.
  - A sparse TileWorld (or a "chunk present" flag) would fix the client-memory and
    air-for-unloaded issues above. That is Track A's file.
- **Track B (view)**: wired through `ViewPresenter`. Still to do:
  - correction smoothing in the view;
  - a dig-progress crack overlay (fraction is on the host only; it could ride in snapshots);
  - a tile highlight under the cursor;
  - nameplates (the name is in the actor look).
- **Track G (assets)**: replace the look dictionaries in `ClientWorld.add_remote` and
  `Presenter.attach` with the looks table.

## Next steps

- **Monsters**: `WorldHost.add_monster` with a brain (`think(host, e, dt) -> PlayerInput`),
  already stepped through `PlayerController` at 60 Hz inside the host tick. Spawns come
  from ecology. Snapshots and ENT_ADD already carry the kind.
- **Combat events**:
  - Add C→H ATTACK (u32 req, u8 action, aim) and H→C EVENT (attack resolved: attacker,
    target, hit, damage, roll) to `Protocol`.
  - Have WorldHost resolve hits through `AttackResolver` with the seeded `Dice.rng`, as new
    outbox event types routed by interest.
  - Add HP and conditions to snapshots or a separate reliable STATUS message.
- **Stricter movement checks**: send the inputs with STATE and replay them on the host
  (`PlayerController.step` is deterministic). Correct only when the replay diverges.
- Move the host tick off the render loop, and add per-peer bandwidth control.
