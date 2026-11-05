# Godspark (working title): a simulated D&D world as a co-op sidescroller

## Context

A long-held idea: a Terraria-scale sidescrolling platformer whose world is a running
simulation of a D&D setting. A huge Underdark, biomes with sensible monster ecology, drow
raiding trade caravans, surface cities that trade and fight, civilizations that grow and
shrink with food supply. Later: portals to the Hells and other planes, ending in the
player's ascent to godhood. Content is SRD 5.2.1 only to start. Art uses placeholders until
`monster-forge` meshes arrive.

Decisions made with the user (2026-11-05):

| Topic | Decision |
|---|---|
| Rendering | 2.5D: real 3D scene on a side-on plane; monster-forge GLBs used directly |
| Terrain | Fully diggable and buildable, Terraria-style |
| Combat | Real-time; hits must physically connect, then d20 rules resolve them |
| Multiplayer | Co-op from the start (host-authoritative) |

Defaults I chose (cheap to change now, say so if any is wrong):
- Engine Godot 4.7.1, GDScript, new project at `~/workspace/godspark`. The name is a placeholder.
- 1 to 4 players, free-roaming anywhere in the world; the host plays (listen server), with a
  `--headless` dedicated mode from the same code. Single-player is a host with no clients.
- Finite worlds (a bounded strip, like Terraria), not infinite.
- Player is an adventurer first; ruling settlements and gathering worshippers come later.

## What already exists and gets reused

- **Rules:** `godot-srd-addon` (submodule at `vendor/godot-srd-addon`, symlink `addons/srd`,
  same layout as `godot-dnd`). `SRDContent.make_monster/make_character/make_spell`,
  `AttackResolver`, `SpellResolver`, `ActiveEffects`, `MonsterActions`, `CombatAI`, `Rest`,
  `LevelUp`, `Items`. `BattleSimulator` (`addons/srd/systems/battle_simulator.gd`) resolves
  fights nobody is watching.
- **Real-time precedent:** Wayfarer already runs SRD combat in real time on this addon
  (`wayfarer/docs/architecture.md`, "Combat"); copy its timing adapter, not its scenes.
- **Monster visuals:** copy `godot-dnd/scripts/monster.gd` (`Monster.load_monster(id)`, LODs,
  clips, hand sockets, props), `tools/sync_monsters.py`, `tools/check_monsters.gd`.
  Today 17 of 330 SRD monsters are rigged and animated, so placeholders matter.
- **Synty art from the asset server** (`http://srv.blastedstudios.com:49200`, 154 cooked
  packs; see "Art sources" below). Reuse from glitchbound: `tools/fetch_assets.sh` (fetches
  only what the project references), `tools/patch_gltf_materials.py`,
  `tools/asset_probe.gd` (AABB sizes), `scripts/world/character_visual.gd` plus
  `anim_retarget.gd` (Synty humanoids with retargeted animation packs).
- **One looks table:** the glitchbound pattern (`glitchbound/data/monsters/looks.json`),
  one table from creature slug to body. Hitbox sizes come from
  `monster-forge/data/registry/srd-5.2.1.json` (`size`, `scale_m`, `speeds`, `body_plan`
  exist for all 330) before any mesh does.
- **Conventions:** headless harnesses that print `ALL PASS`, `xvfb-run` screenshot tools,
  never commit art, setting names in one data file (`data/setting/names.json`).

## Art sources

Each visible thing resolves through a fallback chain, so the game always runs, even on a
fresh clone with no art fetched (which is also how headless tests run).

| Thing | First choice | Then | Last resort |
|---|---|---|---|
| SRD monsters | monster-forge GLB | Synty stand-in where one fits | tinted primitive + nameplate |
| Peoples (townsfolk, guards, drow, dwarves, goblins, bandits) | Synty humanoids via `CharacterVisual` | | primitive |
| Player characters | Synty `Modular_Fantasy_Hero` (gear pieces show equipped items) | | primitive |
| Creatures outside the SRD roster | Synty creature packs | | primitive |
| Terrain blocks | procedural chunk mesh in Synty's flat palette | | flat colours |
| Terrain dressing (trees, rocks, fungi, crystals) | Synty nature packs as tile-anchored objects | | none |
| Buildings | tile stamp for collision + Synty modular pieces and props as the skin | plain structure tiles | |
| UI, icons, FX | Synty interface, icon and particle packs | | Godot defaults |

Packs on the server that map onto the game (all verified in its index):
- **Peoples and player:** `Modular_Fantasy_Hero`, `Fantasy_Characters`, `Knights`, `Vikings`,
  `ElvenRealm`, `Dark_Fantasy`, `Goblin_War_Camp`, `Samurai_Empire`, `Pirate_Pack`.
- **Creatures:** `Fantasy_Rivals`, `Dungeons_Realms`, `Dungeon_Pack`, `Werewolf`, `Kaiju`,
  `Dogs`, `SIMPLE_Forest_Animals`, `SIMPLE_Farm_Animals`.
- **Animation:** `Base_Locomotion`, `Sword_Combat`, `Bow_Combat`, `Idles`,
  `Emotes_And_Taunts`, `Goblin_Locomotion`.
- **Biomes:** `NatureBiomes_MeadowForest`, `_AlpineMountain`, `_AridDesert`,
  `_SwampMarshland`, `_TropicalJungle`, `EnchantedForest`, `Snow_Kit`, `Nature`.
- **Civilizations:** humans `Fantasy_Kingdom`, `Fantasy_Village`, `Farm`; elves
  `ElvenRealm`; dwarves `Dwarven_Dungeon_Map`, `Viking_Realm`; goblinoids
  `Goblin_War_Camp`; drow and the Hells `Dark_Fortress`, `Dark_Fantasy`; desert
  `AncientEgypt`, `AncientEmpire`; coast `Pirate_Realm`; ruins and lairs `Dungeon_Pack`,
  `Dungeons_Realms`.
- **UI and FX:** `INTERFACE_Dark_Fantasy_HUD`, `POLYGON_Icons`, `SIMPLE_Props_Items_Icons`,
  `Particle_FX`.

How Synty fits a diggable tile world:
- **Tiles stay the truth.** Collision, digging and building act on tiles. Meshes are skin.
- **Buildings are templates:** a tile stamp (walls, floors, platforms, doors) plus Synty
  pieces shown as a dollhouse cutaway (back wall and roof kept, front wall hidden). Each
  piece is linked to the tiles it covers, so breaking those tiles removes it. The sim's
  settlement growth stamps these templates; decay swaps them for ruin variants.
- **Dressing objects** (a tree, a market stall, a stalagmite) occupy tile cells, can be
  harvested or destroyed, and replicate as tile-object records, not as scene nodes.
- **Scale check in M0:** Synty modular pieces sit on a metre grid; our tile is 2.5 ft
  (0.76 m). M0 probes the candidate packs with `asset_probe.gd` and fixes the tile's
  metric size and per-pack scale so walls land on tile boundaries.

Risks to watch: (1) monster-forge's inked, painted look against Synty's flat palette; a
shared lighting and outline shader is the first lever, judged from screenshots in M2.
(2) Synty's licence forbids redistributing source assets, so they are fetched, never
committed; a public repo stays runnable through the primitive fallbacks.

## SRD findings that shape the design

- SRD 5.2.1 has **no drow, duergar or mind flayer stat blocks**. "Drow" exists only as an Elf
  lineage and "Underdark" as a term (both verified in the PDF). Drow raiders are therefore
  composed: NPC stat block (Bandit, Scout, Assassin, Mage, Priest, Knight...) plus species
  and lineage traits. This needs one small addon feature, `make_npc(role, species, lineage)`,
  and it gives every civilization (dwarf, elf, orc, halfling, tiefling...) its people for free.
- Underdark natives in the SRD: aboleth, cloaker, darkmantle, grick, roper, rust monster,
  oozes, purple worm, bulette, plus goblinoids, kobolds and gnolls as raider cultures.
- Monster rows carry **no habitat data**, so ecology is authored:
  `data/ecology/habitats.json` (slug to biomes, depth band, time of day, group size, role).
- Planes named in the SRD data: Nine Hells, Abyss, Feywild, Shadowfell, Elemental Planes,
  Astral Plane. 29 fiends, 45 dragon entries, 13 celestials are available as planar and apex
  factions. Epic Boons (7) are the SRD's step past level 20.
- `Dice.roll` uses the global RNG. The host needs seedable dice for tests and replays:
  add an injectable `RandomNumberGenerator` to the addon's `Dice` (only 2 files call `randi`).

## Architecture

Three layers with a one-way dependency: `core` knows nothing about nodes or rendering.

```
core/   pure data and logic, seeded, runs headless      (the host runs this)
net/    host-authoritative session, replication          (talks to core)
view/   3D presentation, input, UI                       (reads replicated state)
```

### core/world: tiles
- Tile = 2.5 ft, so a 5 ft square is 2x2 tiles. Medium creature about 1.5 x 2.5 tiles.
  Reach 5 ft = 2 tiles, Fireball radius = 8 tiles, Darkvision 60 ft = 24 tiles.
- Chunks 32x32 in `PackedByteArray`s: foreground tile, background wall, liquid, flags.
  Sizes: dev 2048x1024, small 4096x1536, medium 8192x2560, large 16384x4096.
- Worldgen is a staged, deterministic pipeline (each stage a pure function of seed):
  heightmap and biome strip, caves, Underdark caverns and long "deep roads", ores, liquids,
  structure sites (settlements, ruins, lairs, portal sites), then sim seeding.
- Tile light engine (sunlight columns, emissive tiles, carried lights). It lives in core
  because rules need it: Bright/Dim/Darkness, Darkvision and Stealth read the same values
  the shader draws.
- Custom swept-AABB tile collision, no Godot physics, so the host can run without a scene.
  SRD speeds become movement modes: Climb (spiders on walls), Fly, Swim, and Burrow that
  really digs (bulette, purple worm).
- Hot paths sit behind a narrow API (`TileWorld`, `ChunkMesher`, `LightEngine`,
  `Pathfinder`) with performance budgets in tests. Port one to a Rust GDExtension only if
  its budget fails.

### core/sim: the living world (two levels)
- **Strategic level**, always running for the whole world, cheap. Settlements (population
  cohorts, food, goods, wealth, garrison, tier), factions (relations, temperament, wars),
  routes (surface roads and deep roads), parties (caravans, raids, patrols, armies,
  migrants, monster packs, as SRD slug counts plus cargo), lairs (monster populations with
  hunger and territory).
  - Food: production from arable tiles and water near a settlement (fungus farms below),
    consumption by population. Surplus grows it, deficit causes starvation, emigration and
    raiding pressure.
  - Trade: prices from stock versus need, caravans dispatched along the most profitable
    route. Raids intercept parties on shared routes. Unwatched fights go to `BattleSimulator`.
  - War and diplomacy: relations drift with raids, trade and border pressure.
  - Chronicle: every event is logged. Tavern rumours and quests are generated from real
    state (escort this caravan, clear the lair starving that town).
- **Materialized level**: when a player's interest bubble overlaps a strategic entity it
  becomes real actors in real tiles (wagons and guards on the road, townsfolk with
  schedules). When the bubble leaves, survivors, cargo and tile damage fold back. Growing
  settlements stamp new buildings; abandoned ones decay into ruins that monsters occupy.
- Each plane is a separate realm (its own tile world, ecology and sim) joined by portals.

### Combat: real-time over d20
- A round is a short real-time budget (start at 2 s, tunable): Action, Bonus Action and
  Reaction are timers; durations scale by rounds. Movement is continuous.
- Melee arcs, projectiles and spell areas are physical. On contact the host calls
  `AttackResolver` / `SpellResolver`. A dodged attack never rolls. Cover comes from tile
  raycasts (`opts.cover`), light and vision from the tile light engine.
- Downed players make death saves and can be stabilized by allies; long rests advance world
  time, so the sim moves while the party sleeps.

### net: co-op
- ENet with one `NetSession` node. The host owns tiles, monsters, dice, loot and the sim.
  Clients own their own movement (host sanity-checks it), which avoids prediction and
  rollback while keeping platforming crisp.
- Messages: compressed chunks, tile deltas, interest-filtered entity snapshots at 10 to
  15 Hz, combat events, sim summaries. Late join supported. Saves live on the host:
  region files, sim state, per-player characters.

### view: 2.5D
- Chunk meshes built on worker threads (front faces, bevelled edges, background wall plane),
  texture array, shader sampling a per-tile light texture, a few real lights for torches and
  spells. Narrow-FOV perspective camera, parallax layers.
- Creatures and people resolve through the looks table (forge GLB, Synty `CharacterVisual`,
  or primitive), yawed to face travel direction. Buildings and dressing are instanced from
  tile-object records (MultiMesh where counts are high).

## Milestones

Each ends in a playable co-op build and green headless suites.

| # | Name | Delivers |
|---|---|---|
| M0 | Foundations | Repo, addon submodule, harness and screenshot tools, architecture doc with stub APIs, seedable `Dice` in the addon, asset fetch plus a Synty survey (contact sheets, module sizes, tile metric decided) |
| M1 | Dig together | Tile world, worldgen v0 (one surface biome plus caves), mesher, lighting, platformer controller, dig and place, 2-player co-op, save and load, Synty hero as the player body, meadow dressing objects |
| M2 | Fight | Characters level 1 to 3 (Fighter, Rogue, Wizard, Cleric first), real-time d20 combat, ecology-driven spawns in 2 biomes plus caves, inventory and loot, death and rests, the looks table (forge, Synty, primitive), visible gear on the modular hero |
| M3 | Living strip | Headless strategic sim: settlements, food, population, trade, raids, chronicle, `tools/run_history.gd`, debug world map. **Runs in parallel with M1 and M2** (pure core) |
| M4 | Materialize | Real tile towns and NPCs built from Synty building templates per culture, shops backed by sim stock and prices, caravans on roads, drow raids you can watch or stop, sim-generated quests, settlements that grow and decay in tiles |
| M5 | The Deep | Full Underdark bands and biomes, drow city-states, deep roads, burrowers, aboleth sea, lair bosses, ores and crafting tiers, levels to 10 |
| M6 | War and dragons | Diplomacy, armies, sieges, dragon lairs and tribute, reputation, player strongholds, levels to 20 |
| M7 | Planes | Realm framework, portals, Nine Hells first, then Abyss, Elemental, Feywild and Shadowfell |
| M8 | Apotheosis | Epic Boons, worshippers as a sim resource, divine trials on the planes, ascension |

The riskiest pieces come first: co-op tile streaming (M1) and whether the sim produces
interesting history (M3). M3 can be judged from text output long before it has graphics.

## How the work gets done

Per the standing preference, I write the architecture doc, interfaces and briefs; Opus
agents implement in git worktrees and I review and integrate. M0 fixes the interfaces so
M1 can split five ways: (A) tile world and worldgen, (B) mesher, lighting, camera,
(C) controller and collision, (D) net session, (E) strategic sim (M3 track).

First session after approval: create the repo, M0, then launch M1 tracks A to E.

## Verification

- `godot --headless -s res://tools/run_tests.gd` prints `ALL PASS`: worldgen golden hashes
  per seed, collision and light unit tests, materialize/fold round-trip conservation,
  performance budgets (chunk mesh under 4 ms, strategic tick for 100 settlements under 2 ms).
- `tools/net_smoke.sh`: a headless host plus a scripted bot client in two processes; the bot
  joins, digs, places, fights, disconnects and rejoins; both sides' tile hashes must match.
- `godot --headless -s res://tools/run_history.gd -- seed=N years=200`: chronicle text and
  population CSV. Checked over many seeds: no negative stocks, trade and raids both occur,
  no total collapse in most seeds, settlements both grow and fall.
- `tools/worldmap.gd` writes a PNG of a generated world (biomes, caves, sites, routes) and
  `xvfb-run` screenshot tools capture gameplay; I look at the images, not just exit codes.
- You playtest each milestone build with a second client; nothing substitutes for that on
  game feel.

## Rules carried over

- SRD 5.2.1 only (CC-BY-4.0 attribution in the repo). No Forgotten Realms names; every
  setting name lives in `data/setting/names.json`.
- Never commit art. `tools/bootstrap.sh` fetches Synty assets from the asset server and syncs
  forge monsters; the primitive fallbacks are procedural.
- Rules content stays SRD 5.2.1. Synty supplies looks, not stat blocks: a creature with no
  SRD stat block gets an original one in our own data, as glitchbound's planar roster does.
- Nothing is pushed to GitHub without your OK.
