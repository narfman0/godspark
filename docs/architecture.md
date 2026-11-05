# Architecture

The design and milestones are in [plan.md](plan.md). This file is the contract between
workstreams: layers, units, and the interfaces each track provides. When code and this file
disagree, fix one of them in the same commit.

## Layers

```
core/   pure data and logic. RefCounted only: no Node, no scene tree, no rendering, no
        Input. Seeded and deterministic. The host runs it headless.
net/    host-authoritative session and replication. Talks to core.
view/   3D presentation, input capture, UI. Reads core state, never owns rules.
game/   boot scenes that wire the three together.
```

`core` must never reference `net`, `view` or `game`. `view` must work as a pure reader:
anything a rule needs (light levels, collision, reach) lives in core.

## Units and conventions

- Tile coordinates: x right, y up, `(0, 0)` bottom-left. Outside the grid reads as bedrock.
- One tile = 2.5 ft (`K.TILE_FT`), so SRD distances convert with `K.ft(feet)`.
  A 5 ft square is 2x2 tiles. A Medium creature's box is about 1.5 x 2.5 tiles.
- Entity position = bottom centre of its box, in tile units (floats).
- View: tile `(x, y)` maps to `Vector3(x * K.TILE_M, y * K.TILE_M, 0)`. The camera looks
  down -Z at the XY plane.
- Chunks are 32x32 (`K.CHUNK`). The host ticks at `K.TICK_HZ`.
- Randomness: never the global generator in core. Take a `RandomNumberGenerator` or derive
  one from `(world_seed, a name)`. Rules dice go through the addon's `Dice`, which the host
  seeds via `Dice.rng`.
- Data lives in `data/*.json`. Setting names (places, peoples, planes) only in
  `data/setting/names.json`.

## What exists (M0)

| File | What |
|---|---|
| `core/k.gd` | `K`: constants and `K.ft()` |
| `core/world/tile_defs.gd` | `TileDefs`: tile and wall tables from `data/tiles.json` |
| `core/world/chunk.gd` | `Chunk`: layer arrays, `to_bytes()` / `from_bytes()` (zstd) |
| `core/world/tile_world.gd` | `TileWorld`: get/set per layer, `tile_changed`, `chunk_changed`, `content_hash()`, `meta`, `TileWorld.make_test()` |
| `tools/run_tests.gd` | runs every `tests/test_*.gd` with `run(t: TestLog)`, prints `ALL PASS` |
| `tools/soft_godot.sh` | Godot with a CPU-rendered window, for screenshots |

`data/tiles.json` ids are stable. Tracks append in their own range so merges stay clean:
tiles 8-15 movement (platforms, ladders), 16-63 worldgen (ores, biome blocks), 64+ free.
Walls: 8-31 worldgen.

## Track A: world generation and saving

Owns `core/world/worldgen/`, `core/world/world_save.gd`, `data/worldgen/`,
`tools/worldmap.gd`.

```gdscript
WorldGen.generate(width: int, height: int, seed: int, opts := {}) -> TileWorld
WorldSave.save(world: TileWorld, dir: String) -> Error
WorldSave.load(dir: String) -> TileWorld          # null if missing or unreadable
```

- Generation is a list of named stages run in order. Each stage gets the world and an RNG
  derived from `(seed, stage name)`, so adding a stage never reshuffles the others.
- Writes go through the `quiet` setters; the generator owns the result until it returns.
- `world.meta` schema (JSON-safe: arrays, dictionaries, numbers, strings):

```
surface: [int] * width        y of the highest solid tile in each column
biomes:  [{x0, x1, biome}]    surface strip, left to right, covering the whole width
bands:   {name: [y0, y1]}     depth bands, e.g. sky, surface, caves, deeps, nadir
sites:   [{id, kind, x, y, biome, band, size}]
             kind: settlement | lair | ruin | portal
routes:  [{id, a, b, kind, length}]    a and b are site ids; kind: road | deep_road
```

- `tools/worldmap.gd -- seed=N size=dev out=path.png` writes a picture of the world: tiles
  by colour, sites and routes drawn over it.
- As built (details in `tracks/worldgen.md`): stages write u8 grids that are packed into
  chunks at the end (equivalent to quiet writes; chunks are left unmodified). Site `y` is
  the feet row (first open tile above solid ground). Underground site `biome` is `caves`
  or `underdark`. Route `length` is walking distance in tiles. Sizes: `WorldGen.SIZES`.

## Track B: light and rendering

Owns `core/world/light_engine.gd` and everything under `view/`.

```gdscript
LightEngine.new(world: TileWorld)
light.level_at(x: int, y: int) -> int          # 0..LightEngine.MAX
light.category_at(x: int, y: int) -> LightEngine.Category   # DARK, DIM, BRIGHT
light.sun = 1.0                                # 0 night .. 1 noon
light.add_light(id: int, x: float, y: float, strength: int)  # carried lights
light.move_light(id, x, y); light.remove_light(id)
light.ensure_region(rect: Rect2i)              # light is computed lazily, per region
signal light_changed(rect: Rect2i)
```

- SRD anchor: a torch reads BRIGHT within 8 tiles (20 ft) and DIM out to 16 tiles.
- Sunlight falls down each column until an opaque tile, then spreads. Emissive tiles and
  carried lights add to it. Edits update incrementally.

```gdscript
WorldView (Node3D)
  setup(world: TileWorld, light: LightEngine)
  set_focus(pos: Vector2)                      # tile units; streams chunk meshes around it
  add_actor(id: int, look: Dictionary) -> Node3D    # look: {kind, size: Vector2, color}
  move_actor(id: int, pos: Vector2, facing: int, state := "idle")
  remove_actor(id: int)
ChunkMesher.build(world, cx, cy) -> ...        # thread-safe, runs on WorkerThreadPool
```

- Chunk meshes rebuild on `tile_changed` / `chunk_changed`. Light reaches the shader as a
  texture with one texel per tile, not as vertex data, so light edits never remesh.
- `view/demo.tscn` flies a camera over a world; `tools/shot.gd` saves a picture of it.
- As built ([tracks/view.md](tracks/view.md)): light levels are 0..`LightEngine.MAX` with a
  torch at 85 (bright from 45, dim from 5); the reading is `max(block, sky * sun)`, so time
  of day recomputes nothing. Sources combine by max. Meshing is split into
  `ChunkMesher.snapshot` (main thread), `build_arrays` (worker) and `to_mesh` (main thread);
  about 0.9 ms per chunk. All shaders are unshaded and read the light textures through
  global uniforms (`gs_*` in project.godot): any actor material must include
  `view/shaders/light.gdshaderinc` and call `gs_light_at()` or it will ignore cave darkness.
- Light for newly seen chunks is spread over frames (`LightEngine.deferred`); one cold
  chunk is still an 8 ms flood on the main thread.

## Track C: bodies, movement, tile interaction

Owns `core/entity/` and `core/world/tile_edit.gd`.

```gdscript
Body            pos: Vector2, vel: Vector2, size: Vector2, facing: int,
                on_floor, on_wall, on_ceiling, in_liquid
TileCollision.move(world: TileWorld, body: Body, dt: float) -> void   # swept, no tunnelling
PlayerInput     move_x, jump (held), jump_pressed, down, up, ...; to_bytes() / from_bytes()
MoveStats       from SRD speeds: walk, climb, swim, fly, burrow (ft per round)
PlayerController.step(world, body, input, stats, dt) -> void          # fixed 60 Hz steps
TileEdit.can_dig(world, body, x, y) -> bool
TileEdit.dig_time(tile_id: int, tool_power := 1.0) -> float
TileEdit.can_place(world, body, x, y, tile_id, bodies: Array) -> bool
```

- Platformer feel: coyote time, jump buffering, variable jump height, automatic step-up of
  one tile, one-way platforms, ladders. Tunables in `data/movement.json`; as built: run
  13 tiles/s at walk 30, jump about 6.5 tiles, reach 4 tiles from the box edge.
- The controller steps at a fixed 60 Hz, so the host runs two steps per 30 Hz tick.
  `step` is deterministic: the host can replay a client's inputs to check its position.
- Also there: `Body.for_size(size_name)`, `TileEdit.DigProgress` (held dig on one tile),
  `TileCollision.raycast(world, from, to) -> {hit, tile, id, point, normal, distance}`
  (line of sight, cover), `overlaps_solid`, `ground_under`. A ladder's top rung can be
  stood on. Details and known weak spots: [tracks/movement.md](tracks/movement.md).
- The same code runs on a client (its own player) and on the host (monsters, validation).

## Track D: net and boot (starts when A, B and C have landed)

Owns `net/`, `core/host/`, `game/`, `tools/net_smoke.sh`.

- `WorldHost` (core): the authoritative loop. Entities by id, tile edits, tick.
- `NetSession` (net): ENet. Host owns tiles, monsters, dice, loot, sim. A client owns its
  own movement and sends it; the host sanity-checks it.
- Messages: chunk blobs (`Chunk.to_bytes`), tile deltas, entity snapshots filtered by
  interest, events. Late join. Single-player is a host with no clients.
- `tools/net_smoke.sh`: headless host plus a scripted bot client in two processes; both
  sides' `content_hash()` must match at the end.

As built ([tracks/net.md](tracks/net.md)): `core/host/` holds `WorldHost`, `HostEntity`,
`ClientWorld`, `Interest`, `ChunkHash`; `net/` holds the protocol, transports (ENet,
loopback), `HostEndpoint`, `ClientEndpoint`, `NetSession`, `BotClient`. The listen host's own
player is an ordinary client over an in-process link. `game/main.gd` boots every mode
(see its header) and takes the world from `WorldSave.load`, else `WorldGen.generate_named`.
Interest is a square of chunks (radius 2, dropped past 3). Open issues: [todo.md](todo.md).

## Hardening (M1 close)

As built ([tracks/hardening.md](tracks/hardening.md)). Changes to the contracts above:

- **Host thread.** `NetSession` ticks the host on its own thread at a fixed `K.TICK_HZ`.
  Touch a running host only through `session.host_call(f)` (runs on the host thread) or
  `session.with_host(f)`; `halt_host()` before saving. HostEndpoint signals fire on the host
  thread (connect them deferred). `LoopbackHub` is thread-safe.
- **Sparse worlds.** `TileWorld.new(w, h, seed, sparse := true)` is a client mirror.
  - Chunks exist between `ensure_chunk` and `unload_chunk`, and `chunk_at` may return
    null.
  - An unloaded cell reads as bedrock (solid, unbreakable) and ignores writes.
  - Light reads it through `light_fg`: air above `world.sky_line` (meta.surface), rock
    below. The view draws nothing for it.
  - Hosts, worldgen and saves stay dense.
- **LightEngine** stores a 2 KB page per computed chunk. With `deferred = true` (the view)
  whole-chunk changes queue up, and `process(budget_us, want)` works through them and cold
  chunks within a budget.
- **Protocol 5** adds META, CLOCK, CHRONICLE and OBJECTS. CHUNK blobs may carry dressing
  records.
- **Client prediction.** `ClientWorld` shows digs and places before the host answers and
  settles each cell to the host's value from the ordered stream (RESULT carries it). Own
  corrections blend in the view (`view_pos()`).
- **Time.** `WorldClock` (core) counts host ticks; a day is `K.DAY_SECONDS` = 1200 s. The
  host owns it, saves it in `host.json` and replicates it. `WorldClock.sun_at(hours)` drives
  `LightEngine.sun`; at night it is `MOON` = 0.04, SRD Darkness on open ground. The view
  draws it moonlit.
- **Living world.** `WorldHost.sim` = `WorldSim.from_meta(world.meta, seed)` for worlds
  with sites. It follows the clock under `SIM_BUDGET_US` per tick, is saved exactly in
  `sim.bin`, and its new chronicle entries go to clients as text lines.
- **Dressing.** `Dressing` (core) holds the id table, from `data/dressing.json`'s
  append-only `ids`, and the rules. Records `(id, x, y, variant)` live in their anchor
  chunk (`Chunk.objects`). The worldgen stage `dressing` places them; they are saved and
  sent with chunks. The host removes an object whose support is dug or whose footprint gets
  a solid tile, and sends OBJECTS. Objects never block movement.
- `TileCollision.depenetrate(world, body)` pushes a body out of solid tiles (used at spawn).
  `TileCollision.move` lands a fast diagonal fall on a ledge corner. `TileEdit.dig_time`
  is exact (WorldHost has no dig epsilon).

## Track E: the strategic simulation

Owns `core/sim/`, `data/sim/`, `tools/run_history.gd`.

```gdscript
WorldSim.from_meta(meta: Dictionary, seed: int) -> WorldSim   # sites and routes from worldgen
WorldSim.synthetic(n_sites: int, seed: int) -> WorldSim       # a made-up strip, for tests
sim.step(hours: int)
sim.to_dict() / WorldSim.from_dict(d)
sim.chronicle                                                  # [{t, kind, ...}]
```

- Settlements, factions, routes, parties, lairs; food, population, trade, raids, war.
  Details in plan.md, "core/sim".
- Party composition is SRD monster slugs with counts. Strength comes from CR; unwatched
  fights resolve through the addon's `BattleSimulator` or a faster stand-in calibrated
  against it.
- `tools/run_history.gd -- seed=N years=200` prints the chronicle and writes a population
  CSV. This is how the sim is judged.

As built ([tracks/sim.md](tracks/sim.md)): `core/sim/` holds `WorldSim`, `SimEconomy`,
`SimConflict`, `SimCombat` and the state classes; data in `data/sim/` (cultures, goods,
lairs, names). Unwatched fights use `SimCombat` (27 us per fight, counts Multiattack),
not `BattleSimulator` (1 ms, first attack only). Exact save and resume goes through
`var_to_bytes(sim.to_dict())`; JSON loses the last bit of some floats. Also there:
`sim.entities_near(x0, x1)`, `sim.party_position(party)`, `sim.audit()`.
`tools/run_history.gd -- seed=N years=80 world=dev` runs it on a generated world.

## Track G: assets

Owns `tools/fetch_assets.sh`, `tools/sync_monsters.py`, `tools/bootstrap.sh`,
`data/looks.json`, `data/dressing.json`, `view/actors/`. As built
([tracks/assets.md](tracks/assets.md), [assets/survey.md](assets/survey.md)):

- `tools/bootstrap.sh` fetches the Synty files the project references (about 57 MB) and
  syncs finished monster-forge monsters. Everything loads at runtime (no editor import),
  and with nothing fetched every actor is a primitive with a nameplate.
- `WorldView.add_actor(id, look)`: `look` may carry `slug` (an SRD monster slug, or
  `player`, `player:<class>`) or `people` (`human:guard`, `elf:drow:raider`). `Looks`
  resolves it: monster-forge GLB, then Synty model, then primitive.
  `move_actor(id, pos, facing, state, vel)` drives idle, run, jump and fall.
- `K.TILE_M` stays 0.75: a 1.8 m Synty human is 2.4 tiles in the 2.5-tile Medium box.
  Standard Synty building kits have a 3 m storey (4 tiles) and 3.75 m wall bays (5 tiles);
  castle and dungeon kits need scale 0.75, Kingdom house pieces 0.9.
- `DressingView` instances tile-anchored objects (`data/dressing.json`) from `{id, x, y}`
  records. Worldgen places them and the host replicates them (see Hardening).

## M2 contracts (leveling and combat)

Design: [m2.md](m2.md). These are the shapes the M2 tracks share. Tracks own their own
directories and reach the host and the wire only through systems, so they do not edit
`world_host.gd`, `protocol.gd` or the endpoints.

As built for the base ([tracks/m2-base.md](tracks/m2-base.md)); the sections below are
the exact signatures.

### Systems

```gdscript
HostSystem (core/host/host_system.gd): RefCounted, every hook a no-op by default
  const RULES = 1, COMBAT = 2, ITEMS = 3, MONSTERS = 4    # wire ids (u8), stable
  sys_id() -> int
  attach(host: WorldHost)                     # once, when added
  tick(host: WorldHost)                       # every host tick, after movement and digs
  entity_added(host, e: HostEntity)           # players (after load_player) and monsters
  entity_removed(host, e: HostEntity)         # still in host.entities; players after save_player
  handle(host, e: HostEntity, kind: int, data: PackedByteArray)   # SYS from e's owner
  allow_place(host, e, tile_id) -> bool       # false refuses a place (Reason.NO_ITEM)
  tile_edited(host, e, x, y, old, now)        # after a player's dig (now == AIR) or place,
                                              # before its EDIT_RESULT
  save_player(e) -> Dictionary                # stored in the player record: rec.systems["<id>"]
  load_player(e, d: Dictionary)               # on join, {} for a new player
  save_world() -> Dictionary                  # stored in host.json: systems["<id>"]
  load_world(d: Dictionary)
host.add_system(sys: HostSystem)              # also: load_world if load_state already ran,
                                              # then attach, then entity_added for those present
host.system(sys_id) -> HostSystem             # null if absent
host.send_sys(sys_id, kind, data, to_entity := WorldHost.ALL) -> bool    # one player or all
host.send_sys_near(sys_id, kind, data, pos: Vector2) -> bool  # players whose interest covers pos
host.receive_sys(entity_id, sys_id, kind, data) -> bool       # the endpoint calls it
WorldHost.SYS_MAX = Protocol.MAX_SYS = 32768  # payload cap; send_sys refuses bigger

ClientSystem (core/host/client_system.gd)
  sys_id() -> int
  attach(cw: ClientWorld)
  handle(kind: int, data: PackedByteArray)
  frame(dt: float)                            # every client frame, from cw.advance
  allow_place(tile_id) -> bool; placed(req, tile_id)   # place prediction gate (items)
cw.add_system(sys); cw.system(sys_id) -> ClientSystem
cw.send_sys(sys_id, kind, data)               # queued; the endpoint sends it the same frame

Systems (core/host/systems.gd)                # where the game finds them: no boot edits
  Systems.HOST / Systems.CLIENT: id -> script path, e.g. 1: res://core/rules/rules_system.gd
  Systems.install_host(host); Systems.install_client(cw)   # NetSession does both
```

- One wire message, `SYS` (type 32), both directions: u8 system id, u8 kind, payload (rest
  of the packet, at most 32 KiB). Reliable and ordered with everything else; a host SYS goes
  out after the tile deltas queued before it. Each system defines its kinds and byte layouts
  in its own codec file with round-trip tests.
- A SYS for an unknown system id is ignored and logged once (per peer and id on the host,
  per id on a client). Never a kick.
- Hooks run on the host thread. Saved dictionaries go through JSON: numbers come back as
  floats. Records and world state of systems not installed in a run are kept and written
  back unchanged.
- To plug a track in, put its scripts at the `Systems` paths (rules 1, combat 2, items 3,
  monsters 4: `core/<rules|combat|items|monsters>/<name>_system.gd` and `..._client.gd`, see
  the file). `new()` takes no arguments; the shared rules content is `host.srd`.
- Client systems are installed on `ClientEndpoint.welcomed`, before the SYS messages that
  follow WELCOME are read. Tests add systems by hand (`tests/echo_system.gd` is the example).

### Level track (`core/rules/level_track.gd`, pure static functions)

```gdscript
LevelTrack.MAX_LEVEL = 100; MAX_CLASS_LEVEL = 20; XP_SCALE = 15.0   # tools/xp_pacing.gd
enum LevelTrack.Reward { SPARK_SLOT, VIGOR, KNACK, CLASS_LEVEL, EPIC_BOON }
LevelTrack.class_level(level) -> int        # min(20, 1 + level / 5)
LevelTrack.reward(level) -> Reward          # level % 5: 1, 3 SPARK_SLOT; 2 VIGOR; 4 KNACK;
                                            # 0 CLASS_LEVEL, and EPIC_BOON at 100
LevelTrack.count(level, r) -> int           # rewards of kind r in levels 1..level
LevelTrack.spark_slots(level) -> int        # 40 at 100 (level 1 brings the first)
LevelTrack.vigor_steps(level) -> int        # 20 at 100
LevelTrack.knacks(level) -> int             # 20 at 100
LevelTrack.xp_for_level(level) -> int       # total XP; 0 at level 1
LevelTrack.level_for_xp(xp) -> int
LevelTrack.srd_hp(class_level, hit_die, con_mod) -> int    # SRD fixed-value total
LevelTrack.vigor_hp(hit_die) -> int         # ceil(hit_die / 2)
LevelTrack.max_hp(level, hit_die, con_mod) -> int
LevelTrack.hit_dice(level) -> int           # class level + Vigor steps
```

- Between class levels XP and hit points move in fifths: level 5c + p is the SRD value at
  class level c + 1 plus p/5 of the gap to the next (hit points floored, so they never
  fall). The first band (levels 1-4) moves in quarters, so level 1 is exactly SRD level 1.
- Levels 96-100 continue one more band as if there were a class level 21 with the last SRD
  gap: level 100 needs 405000 XP (times XP_SCALE) and has one more class level's worth of
  hit points. `class_level(100)` is still 20.
- `max_hp` is the SRD total at every class level plus `vigor_steps * vigor_hp`. CON is the
  current modifier applied to every level, as the SRD does.

### Character (`core/rules/character.gd`)

One per player, owned by the host, saved in the player record (`rec.character`), mirrored
to its owner by the rules system (CHAR, [tracks/rules.md](tracks/rules.md)).

```gdscript
Character.create(name, class_slug, scores := [], skills := [], species := "", background := "",
        srd: SRDContent = null) -> Character   # level 1; "" / [] take the class default;
                                               # with srd, class level 1 choices are answered
Character.DEFAULTS                     # fighter, rogue, wizard, cleric: scores, skills,
                                       # background, auto_answer prefs, default gear
Character.HIT_DIE                      # class -> SRD hit die
name, class_slug, subclass, species, background: String
level: int (1..100), xp: int
build: Dictionary                      # SRDProgression build {class, scores, skills, choices}
knacks: Array; deeds: Dictionary
sparks, inventory, equipment: Dictionary   # placeholders: the items track replaces them
hp, hit_dice_left: int; slots_left: Array; uses_left: Dictionary
bed: Vector2i or null
class_level() -> int; hit_die() -> int; con_mod() -> int
max_hp() -> int                        # LevelTrack.max_hp with the resolved CON
hit_dice_max() -> int; spark_slots() -> int
resolved() -> Dictionary               # SRDProgression.resolve at class_level()
auto_choices(srd) -> int               # answer every open SRD choice (auto_answer + prefs)
pending_choices(srd) -> [{class_level, choice}]
answer_choice(class_level, choice_id, answer: Array)    # hp follows a changed max
gain_level() -> LevelTrack.Reward      # +1 level: hp and Hit Point Dice grow with the max;
                                       # choices and Knacks stay open for the rules track
make_combatant(srd) -> Combatant       # make_character at class_level() with the resolved
                                       # build and default gear; max_hp = LevelTrack.max_hp,
                                       # current hp and hit dice from the record
capture(c: Combatant)                  # hp and hit dice back into the record
move_stats(c: Combatant = null) -> MoveStats   # from_srd({walk: c.speed}, "medium")
to_dict() -> Dictionary; Character.from_dict(d) -> Character   # JSON-safe, exact round trip
```

- Species and background are labels for now (the addon's make_character takes neither).
- Make the combatant first, then `ItemEffects.apply` gear on it. Note: the addon's
  ItemEffects recomputes max hit points for a CON change as `con_delta * stats.level`
  (class level), which is not what `LevelTrack.max_hp` does for the levels between; the
  items track should re-derive max hit points from the level track after applying gear.

### Entities and hit points on the wire

```gdscript
HostEntity.character: Character        # players
HostEntity.combatant: Combatant        # players and monsters; null allowed
HostEntity.vitals() -> Vector2i        # (hp, max) or HostEntity.NO_VITALS
host.add_player(name, owner, opts := {})   # opts.class: SRD class for a new character
host.default_class = "fighter"
host.add_monster(stats, pos, brain, look := {}, combatant: Combatant = null)
host.add_srd_monster(slug, pos, brain = null) -> HostEntity   # null for an unknown slug
WorldHost.monster_size(stat_block) / monster_speeds(stat_block)
host.srd  /  WorldHost.shared_srd() / WorldHost.warm_srd()    # one SRDContent per process
cw.hp, cw.max_hp; cw.vitals_of(id) -> Vector2i; RemoteEntity.hp / max_hp (-1: none)
signal ClientWorld.vitals_changed(id, hp, max_hp)
Presenter.actor_vitals(id, hp, max_hp)  # optional; LogPresenter prints it
```

- Protocol 6. HELLO gains an optional `str class`. ENT_ADD gains u16 hp, u16 max_hp
  (max 0: none). New `VITALS` (type 33, reliable): u8 n, n x (u32 id, u16 hp, u16 max_hp),
  sent on snapshot ticks with only the values that changed since the peer last heard, for
  entities it sees and its own player. SNAPSHOT stays 17 bytes per entity.
- `WorldHost.tick()` installs its own seeded `Dice.rng` first, so the rules dice are always
  the ticking host's. Only host-thread code (ticks, system hooks, `host_call`) may roll.
- `main.gd` options: `class=SLUG` (any client mode), `spawn=SLUG[:N]` (host: N monsters
  left of the spawn point, no brain). The bot prints `BOT <name> vitals me=hp/max sees ...`.

### Items (`core/items/`)

As built ([tracks/items.md](tracks/items.md)).

```
Item record (a Dictionary, JSON-safe):
  {base, count, material?, quality?, affixes?: [id or "id:tier"], magic?: slug, tier?: int,
   spark?: {id, rank}, bonded?: true}
  base      SRD weapon/armour slug, "tile:<name>", a data/items/base.json row (coin, spark,
            ingot:iron, cloth ...), or an SRD magic item slug (non-weapon magic: base == magic)
  magic     an SRD magic item slug (addon magic_items.json); tier: its variant (+N - 1, damage
            type, giant, potion potency); bonded: attuned at a campfire (cleared when dropped)
Items.mods(item, active_only := false) -> Array   base, material, quality, affixes, magic;
                                       the +3 to-hit/AC budget applied here (Items.BUDGET)
Items.tags(item) -> Dictionary         game effects (dig_speed, light, pickup_radius, ...)
ItemGen.roll(rng, base, level_hint, rank) -> item; ItemGen.name(item)
Inventory   10 hotbar + 40 bag slots, stacking, coin: int, selected; add(item) -> leftover,
            take(slot, n), move(a, b), tile_slot(tile), to_dict()
Equipment   head, neck, cloak, armor, hands, belt, feet, main_hand, off_hand, ring_1..ring_10;
            can_equip(item, slot) -> "" or reason; mods_list(); tags(); dress(c, character, srd)
Constellation   slots (from LevelTrack.spark_slots), kindled: [{id, rank, at}]; kindle(spark),
            swap(i, spark) -> old; sigil()
Sparks.apply(kindled, stats: MoveStats, out: Dictionary); Sparks.move_stats(speeds, size, kindled)
Loot.roll(rng, info) -> [item]; Drops (loot on the ground, owned by the items system)
Character.inventory / equipment / sparks are Inventory / Equipment / Constellation (saved there)
```

- Unified slot indices (wire and UI): 0-9 hotbar, 10-49 bag, 50-68 `Equipment.SLOTS`.
- The edit flow: `HostSystem.allow_place(host, e, tile_id) -> bool` and
  `HostSystem.tile_edited(host, e, x, y, old, now)`; `WorldHost.Reason.NO_ITEM`;
  `ClientSystem.allow_place(tile_id) -> bool` and `ClientSystem.placed(req, tile_id)`.
  Digging gives the tile's item, placing takes one; the client predicts only what it holds.
- Spark movement: `MoveStats.air_jumps / air_jump_mult / dash_* / glide_fall` (off by
  default), the matching `Body` state, `PlayerInput.dash` (flag bit 7). Players' `e.stats`
  is set by the items system (base speeds + sparks); the owner gets the same inputs (STARS)
  and computes the same `cw.stats`.

### Combat (`core/combat/`)

As built ([tracks/combat.md](tracks/combat.md)). `CombatSystem` (HostSystem.COMBAT) and
`CombatClient`; byte layouts in `CombatCodec`.

```
Intents, client -> host (SYS kinds 1-3; no USE: items and features are not wired yet):
  ATTACK {aim: Vector2, clock, throw}     CAST {slug, level, aim, clock}     CANCEL
  clock = ClientWorld.clock: the host estimates the one-way delay from it and leads the
  attacker's body by vel * delay when it tests hit shapes
Host -> client: EVENTS (to players near, one message per chunk per tick), STATUS and
  SPELLS (to the owner)
CombatEvent {t: tick, kind, src, dst, ...}: SWING (mode, swings, windup, total, aim, what) |
  HIT | MISS | CRIT (d20, total_roll, ac) | SAVE (dc, saved, what) | DAMAGE (amount, dtype, hp) |
  HEAL (amount, hp) | CONDITION (cond, on) | DOWNED | DEATH | XP (amount; reserved) |
  EFFECT (on, what) | PROJECTILE (pid, pkind, pos, vel, gravity) | IMPACT (pid, pos) |
  PUSH (push) | CANCEL
# brains (host thread)
combat.can_act(e); combat.busy(e); combat.start_attack(e, action := -1, aim, throw := false) -> bool
combat.targets_in_reach(e, action := -1) -> Array[HostEntity]; combat.nearest_foe(e, tiles)
combat.actions_of(e) -> Array; combat.filter_input(e, inp) -> PlayerInput   # brains must call it
# others
combat.damage(src_id, dst, amount, dtype, opts := {}) -> int; combat.in_combat(e) -> bool
combat.cast(e, slug, level, aim) -> String ("" ok); combat.cancel(e); combat.is_downed(e)
# client (UI)
signal event(ev), cooldowns_changed(status), spells_changed(spells)
cc.attack(aim, throw := false); cc.cast(slug, level, aim); cc.cancel(); cc.spell_slot(i)
cc.filter_input(inp); cc.events_log; cc.status; cc.spells
Presenter.combat_event(ev)     # optional; LogPresenter prints it, ViewPresenter plays one-shots
```

- Tempo and durations come from `data/combat.json`. Every weapon hit goes through
  `AttackResolver.weapon_attack` (the sweep of a wide arc is the game's own reduced roll) and
  every spell through `SpellResolver.cast`; positional facts are measured on the host (cover
  from 3x3 raycasts, within 5 ft box to box, unseen from a host LightEngine plus player
  torches and Darkvision, ranged in melee, long range).
- Monster combatants are renamed `"<name> #<id>"` (the addon keys effects by name).
- A player's position is moved by the host only through `WorldHost.teleport` (the fallback
  respawn); pushes on players are a PUSH event the owner applies to its own body.

### Monsters (`core/monsters/`)

As built ([tracks/monsters.md](tracks/monsters.md)). `MonstersSystem` (HostSystem.MONSTERS)
and `MonstersClient`; byte layouts in `MonstersCodec`; data in `data/ecology/`.

```
monsters.spawn(slug, pos, opts := {}) -> HostEntity   # opts: rank, affixes, home, pack, slot, brain,
                                                    #   lair, group, combatant (make_npc), people, name, scale
monsters.request_plan(e, goal, tol)                 # brains; MonsterBrain.on_plan(path) answers
monsters.director_enabled: -1 auto | 0 | 1          # main.gd host option spawns=0|1
monsters.on_combat_damage(e, dealt, src)            # combat's damage hook (any system may define it)
MonsterNav.profile(stats, dig := 0.0) -> NavProfile; MonsterNav.start(world, prof, from, to, tol, partial,
    max_expand) -> NavSearch; search.step(n, budget_us := 0) -> bool; search.result() -> NavPath
NavFollow.set_path(p); follow.input(world, body, dt, dig_rate) -> PlayerInput (null: done or failed)
Ecology.habitats() / spawning() / affixes() / row(slug) / roster(srd, band, biome, night, lo, hi, water)
# entity meta set at spawn (Object meta): rank, xp_mult, friendly (neutral); look: slug | people,
#   rank, scale, affixes
# client
signal monster_info(id, info), monster_gone(id); mc.info_of(id); mc.look_of(id)
# addon
SRDContent.make_npc(role, species, lineage := "", id := 0) -> Combatant; Combatant.senses (ft)
WorldSim.lair_killed(site_id, slug, by := "adventurers") -> bool
combat.set_pace(e, mult)
```

- Ranks: minion (1 HP, xp 0.25), standard, elite (hit dice maximum, 1 affix, xp 2), champion
  (double, 2 affixes, scale 1.3, xp 4), boss (as written, xp 6). Rules reads `rank`/`xp_mult`
  meta; Items reads `look.rank`.
- SYS kinds (host -> client): INFO 1 (rank, slug, people, scale, flags, affixes per monster,
  sent when it enters a player's interest), GONE 2.
- Lairs: materialized from `host.sim.lairs` near players, reconciled each second, kills written
  back with `WorldSim.lair_killed`, survivors folded back; nothing extra saved.

### Integration (as built: [tracks/m2-integration.md](tracks/m2-integration.md))

```gdscript
# protocol 7: ENT_ADD gains str slug, str people, u8 rank (Protocol.RANKS), u8 scale*20
Protocol.ent_add(..., hp, max_hp, look := {}); Protocol.compact_look(look)
cw.add_remote(..., look := {}); RemoteEntity.look       # actor_added carries slug/people/rank/scale
ClientSystem.decorate_look(id, look)                    # fill gaps before actor_added (monsters: INFO)
# who may act, how players may move
HostSystem.allow_edit(host, e) -> bool                  # rules: not while downed; refusal Reason.UNABLE
ClientSystem.allow_edit() -> bool                       # the same gate for prediction
HostSystem.move_limits(host, e) -> {mult?, no_jump?, fear?}   # combat: conditions, downed
WorldHost.move_limits(e); WorldHost.can_edit(e); WorldHost.teleport(e, pos)   # CORRECT + epoch for players
WorldHost.HOLD_SLIP; HostEntity.hold_at                 # speed 0: anchored, may only fall
# reach and dig speed (Longarm, Mole, gear): host and client compute the same
HostEntity.edit_reach / dig_power; cw.edit_reach / dig_power; Items.edit_numbers(tags) -> Vector2
TileEdit.in_reach(body, x, y, reach := REACH); can_dig(..., reach); can_place(..., bodies, reach)
DigProgress.update(at, id, dt, tool_power)
# rules mirrors (RulesCodec): DEEDS 8, SUMMARY 9 (SheetSummary.of JSON), PREFS 10, SET_PREFS 72
rc.deeds / rc.summary / rc.prefs; signals deeds_changed, summary_changed, prefs_arrived; rc.set_prefs(d)
rules.is_resting(e); rules.xp_rate (host option xp=N); Character.prefs; Character.clean_prefs(d)
# combat: STATUS gains u16 temp_hp; REFUSED 19 (u8 intent, str reason) -> cc.refused(intent, reason)
# items: Inventory.ATTACK_SLOT (0): never filled by add/first_free; new characters start on it
# monsters: SpawnDirector.spawn_pack(pack, spot, band); band_def_at(h, band, pos) (ramp near
#   settlements); killed(rec, band, night) -> a lull; spawning.json ramp, lull_s, nadir promote
```

- Combat calls `rules.player_dropped(e, crit)` for every hit that lands on a player at 0 HP,
  and `rules.heal` when a spell raised a downed player. Items' potions heal through
  `rules.heal`. Spells on allies may target a downed player.
- `rules.refresh` ends with `items.outfit(e, c)` (weapon, armour, shield, masteries, mods).
- `Character.capture` keeps HP above the gear-less max (gear CON) and copies slots and uses
  left; the rules tick captures every SYNC_EVERY ticks, so a save always has them.
- Downed and dead players cannot dig, place, use, drop, bond, kindle or pick up.
- Worldgen stage `cave_steps` (after `caves`): widens pinch points in the caves band and
  hangs ladders up tall cave walls.

### Wave 1: who owns what, and how systems call each other

| Track | System id | Owns |
|---|---|---|
| Rules | `HostSystem.RULES` | `core/rules/` (beyond `level_track.gd` and `character.gd`, which it may extend), `data/rules/` |
| Combat | `HostSystem.COMBAT` | `core/combat/`, `data/combat.json`, attack and cast input actions, `tools/arena.gd` |
| Items | `HostSystem.ITEMS` | `core/items/`, `data/items/`, `data/loot/`, `data/sparks.json`, tiles 64-95 |
| Monsters (wave 2) | `HostSystem.MONSTERS` | `core/monsters/`, `data/ecology/`, `tools/ecology_report.gd`, `tools/spawn_sim.gd` |

Systems find each other with `host.system(id)` and must work when the other is absent
(check for null and `has_method`). The calls each one offers:

```gdscript
# Rules (as built: tracks/rules.md)
rules.on_kill(victim: HostEntity, killers: Array[int])   # XP to players within 24 tiles and
                                      # the killers, deeds; rank from meta "rank" / "xp_mult"
rules.award_xp(entity_id, n, source := "") -> int        # levels gained
rules.add_deed(entity_id, counter: String, n := 1)       # counters: see core/rules/knacks.gd
rules.refresh(e: HostEntity)          # rebuild the combatant and move stats after gear, sparks
                                      # or a level change; keeps current HP in range; resyncs
rules.player_dropped(e, crit := false)   # combat reports 0 HP, and every hit on a player at
                                      # 0 HP (a failed death save; two on a crit)
rules.heal(e, amount) -> int          # healing that also gets a downed player up (the addon's
                                      # heal does nothing at 0 HP)
rules.is_downed(e) -> bool            # downed, stable or dead; rules.is_dead(e)
rules.bond(entity_id, key) -> int     # "people:<culture>", "beast:<kind>"; 0 = none
rules.proficiencies(entity_id) -> {skills, tools, languages}
rules.extras(e) -> Dictionary         # what items.apply_sparks wrote to `out`
# Items
items.gear_mods(e) -> Array           # ItemEffects mods of everything worn (unbonded magic out)
items.wielded(e) -> Dictionary        # the main-hand item record, {} if none
items.outfit(e, c := e.combatant)     # weapon, armour, shield, mods; max HP from LevelTrack
items.apply_sparks(e, stats: MoveStats, out: Dictionary)
items.tags(e) -> Dictionary           # gear + spark tags (swing_recovery, reach, light ...)
items.give(entity_id, item: Dictionary) -> Dictionary     # leftover, {} when it all fit
items.drop(pos: Vector2, items: Array, from := 0)          # loot on the ground
items.on_kill(victim: HostEntity) -> Array   # roll the loot table and drop it; rank from
                                      # victim.meta.rank or victim.look.rank
items.refresh(e)                      # calls rules.refresh(e) if present (which should call
                                      # items.outfit), else outfit; then sets e.stats
# Combat
combat.damage(src_id, dst: HostEntity, amount, dtype, opts := {})   # for traps, falls, effects
combat.in_combat(e) -> bool           # hostile activity within the last few seconds
```

Campfire, bed and shrine are tiles (64, 65, 66), so rests and kindling test for a tile near
the player and need no other system.

Rules as built: `RulesSystem` / `RulesClient` (`core/rules/`), wire format in
`rules_codec.gd`, the client surface for the interface in [tracks/rules.md](tracks/rules.md).
Downed and respawned players are held and moved by the host through `WorldHost.teleport`. Short rest: campfire within 3 tiles, nothing hostile within
12, 5 s. Long rest: bed within 2 tiles, no daily limit (if it is safe, you can sleep); the night passes (to 06:00)
when every living player is in bed. Downed: a death save every 4 s; revive is a 2 s hold
within 3 tiles; respawn at the bed, else the nearest shrine within 96 tiles, else the spawn. Presentation is wave 2: in wave 1 a track may add one
optional no-op method to `Presenter` (the log presenter prints it) and nothing else in
`game/` or `view/`, except that Combat owns the attack and cast inputs.

## M4 contracts (the living world on screen)

Design: [m4.md](m4.md). New system ids: `HostSystem.LIFE` (5, `core/life/`) and
`HostSystem.DEALS` (6, `core/deals/`), found by `core/host/systems.gd` like the others.

### Places and routes (`core/world/places.gd`, exists)

Worldgen writes them into `world.meta`; everyone reads them through `Places`.

```
meta.places: {"<site id>": {site, rect: [x, y, w, h], culture, tier,
                            buildings: [{kind, rect, door: [x, y], anchors: {role: [[x, y]]}}]}}
   kind:    home | smithy | market | tavern | shrine | gate | hall | store | ruin
   anchors: feet cells where a person of that role stands or works
            (smith, merchant, keeper, priest, guard, townsfolk)
meta.routes[i].path: [[x, y], ...]   feet cells from site a to site b, walkable by a
                                     Medium body without digging (and by a wagon on roads)
Places.place(world, site_id), buildings(world, site_id, kind), anchors(world, site_id, role),
Places.route_path(world, route_id), route_point(world, route_id, t)
```

Tiles stay the truth: a building is a tile stamp (walls, floors, doors, platforms) plus
dressing records for its skin. The sim's settlement tier decides how many buildings stand.

### Life (`core/life/`, system 5)

Turns sim entities into actors while a player is near, and back.

```
Entity meta set by Life on what it spawns:
  sim:      {kind: settlement | party | lair, id, role}   role: townsfolk, guard, smith,
            merchant, keeper, priest, escort, raider, drover, wagon ...
  faction:  the sim faction id as a string, or "wild"
  talk:     true when a player can talk to it
life.stance(a: HostEntity, b: HostEntity) -> int      # Life.HOSTILE, NEUTRAL, FRIENDLY
life.faction_of(e) -> String                          # players: "players"
life.standing(entity_id, faction) -> int              # -100..100, the player's standing
life.add_standing(entity_id, faction, n, why)
life.actors_at(site_id) -> Array[HostEntity]; life.actors_of(party_id) -> Array[HostEntity]
```

- Combat and brains pick foes through `life.stance` when Life is installed (monsters fight
  guards, guards fight raiders); without it, monsters and players are foes as before.
- While materialized, the sim entity is frozen (the sim skips it); on fold-back its people,
  cargo and coin are written back. Counts are conserved: a test proves it.
- Dice for materialized things come from per-entity seeded generators, so looking at the
  world does not change the sim's own rolls.

### Deals (`core/deals/`, system 6; wave 2)

Talk, trade, quests and patrons. Reads `host.sim`, `Places` and Life's roles; pays out
through Items (`give`), Rules (`award_xp`, `add_deed`) and Life (`add_standing`).

### Traversal

- `S` (down) drops through a one-way walkway when there is open space below; no jump needed.
- Ropes: an item anchored at a cell; it hangs down through open cells to the floor or its
  length, and is climbed like a ladder (W up, S down).
- Worldgen guarantees: every site, cave region and cavern is reachable on foot from the
  spawn settlement by a Medium walker without digging.
- Digging yields `rubble`; ore tiles yield an ore trade good. `supplies` make camp gear.

