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

### Systems

```gdscript
HostSystem (core/host/host_system.gd), one per feature area, added with host.add_system(sys)
  sys_id() -> int                       # 1 rules, 2 combat, 3 items, 4 monsters
  attach(host: WorldHost)
  tick(host)                            # every host tick, after movement
  entity_added(host, e: HostEntity); entity_removed(host, e)
  handle(host, e: HostEntity, kind: int, data: PackedByteArray)   # from e's owner
  save_player(e) -> Dictionary; load_player(e, d: Dictionary)     # merged into the player record
  save_world() -> Dictionary; load_world(d: Dictionary)
host.send_sys(sys_id, kind, data, to_entity := ALL)   # ALL: every player; or one entity id
host.send_sys_near(sys_id, kind, data, pos: Vector2)  # players whose interest covers pos
host.system(sys_id) -> HostSystem

ClientSystem (core/host/client_system.gd), the client-side half
  sys_id() -> int
  attach(cw: ClientWorld)
  handle(kind: int, data: PackedByteArray)
  frame(dt: float)
cw.send_sys(sys_id, kind, data); cw.system(sys_id) -> ClientSystem
```

On the wire both directions use one message, `SYS`: u8 system id, u8 kind, payload. Each
system defines its own kinds and byte layouts in its own codec file with round-trip tests.

### Level track (`core/rules/level_track.gd`, pure functions)

```gdscript
LevelTrack.MAX_LEVEL = 100
LevelTrack.class_level(level) -> int        # min(20, 1 + level / 5)
LevelTrack.reward(level) -> Reward          # SPARK_SLOT (level % 5 in 1, 3), VIGOR (2), KNACK (4), CLASS_LEVEL (0)
LevelTrack.spark_slots(level) -> int        # 40 at level 100
LevelTrack.vigor_steps(level) -> int; LevelTrack.knacks(level) -> int
LevelTrack.xp_for_level(level) -> int       # SRD gap between class levels split in five, times XP_SCALE
LevelTrack.max_hp(level, hit_die, con_mod) -> int   # SRD total at each class level, a fifth of the
                                                    # next gain per level between, plus Vigor
```

### Character (`core/rules/character.gd`)

One per player, owned by the host, saved in the player record, mirrored to its owner.

```
name, class_slug, subclass, species, background
level (1..100), xp
build            the addon's SRDProgression build: {class, scores, skills, spells?, choices}
knacks: [id]; deeds: {counter: n}
sparks           Constellation (items track): slots from the level, kindled sparks in order
inventory        Inventory (items track); equipment: Equipment (items track)
hp, hit_dice_left, slots_left, uses_left      state that rests restore
bed: Vector2i or none                         where death and long rests return you
to_dict() / Character.from_dict(d)            JSON-safe
make_combatant(srd: SRDContent) -> Combatant  the addon Combatant at class_level(level), with
                                              track hit points, gear mods and nothing from sparks
move_stats() -> MoveStats                     SRD speeds plus spark and gear changes
```

`HostEntity.character` (players) and `HostEntity.combatant` (players and monsters) hold
them. Snapshots carry hit points and max hit points for every entity with a combatant.

### Items (`core/items/`)

```
Item record (a Dictionary, JSON-safe):
  {base, count, material?, quality?, affixes?: [id], magic?: slug, spark?: {id, rank}}
  base      a row id in data/items/*.json: SRD weapons and armour by slug, tiles by name
            ("tile:stone"), materials, consumables, campfire, bed
  magic     an SRD magic item slug (addon magic_items.json)
Items.mods(item) -> [Dictionary]      ItemEffects mods (addon format) from base, material,
                                      quality, affixes and magic
Inventory   slots, stacking, hotbar; add(item) -> leftover, take(slot, n), to_dict()
Equipment   slots: head, neck, cloak, armour, hands, belt, feet, main_hand, off_hand,
            ring_1 .. ring_10; can_equip(item, slot); mods_list() for ItemEffects.apply
Constellation   slots: int, kindled: [{id, rank}]; kindle(spark), swap(i, spark)
Sparks.apply(kindled, stats: MoveStats, out: Dictionary)   movement and living only; a test
                                                            proves no spark changes an attack
                                                            roll, AC, save DC or damage die
```

### Combat (`core/combat/`)

```
Intent, from a client: {kind: ATTACK | CAST | USE, aim: Vector2 (tile units), what: slot or spell}
CombatEvent, host to clients near it:
  {t: tick, kind: SWING | HIT | MISS | CRIT | SAVE | DAMAGE | HEAL | CONDITION | DOWNED | DEATH | XP,
   src: entity id, dst: entity id, amount, dtype, roll?, what?}
Tempo and durations come from data/combat.json. Every weapon hit goes through the addon's
AttackResolver.weapon_attack and every spell through SpellResolver.cast; the game supplies
positional facts (cover from TileCollision.raycast, within_5ft, light from LightEngine).
```

