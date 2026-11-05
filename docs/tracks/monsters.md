# Track: Monsters (M2 wave 2)

Branch `ws/monsters`. What makes the world dangerous: tile navigation, brains, the ecology
table, ranks and affixes, the spawn director, lairs from the world sim, and `make_npc` in the
addon. Design: [m2.md](../m2.md), "Monsters"; contract: [architecture.md](../architecture.md),
"M2 contracts / Monsters".

## What was built

| File | What |
|---|---|
| `core/monsters/nav.gd` (+ `nav_search.gd`, `nav_path.gd`, `nav_profile.gd`, `nav_follow.gd`) | `MonsterNav`: per-MoveStats profiles with jumps recorded from the real controller, resumable A* (`NavSearch`), `NavPath`, `NavFollow` (path -> `PlayerInput`, digs) |
| `core/monsters/brains/monster_brain.gd` | `MonsterBrain`: one state machine, nine archetypes |
| `core/monsters/monsters_system.gd` | `MonstersSystem` (HostSystem.MONSTERS): spawn, ranks, affixes, the planner queue, INFO, hooks |
| `core/monsters/affixes.gd` | `Affixes`: the 11 affixes' effects |
| `core/monsters/spawn_director.gd` | `SpawnDirector`: budgets, packs, placement, raiders, despawn |
| `core/monsters/lair_link.gd` | `LairLink`: lairs materialize, reconcile, fold back, write kills back |
| `core/monsters/ecology.gd` | `Ecology`: data access, rosters, CR, max HP from hit dice |
| `core/monsters/monsters_codec.gd`, `monsters_client.gd` | `MonstersCodec` (INFO, GONE), `MonstersClient` |
| `data/ecology/habitats.json` | all 330 SRD monsters |
| `data/ecology/spawning.json`, `affixes.json`, `brains.json` | director and ranks, affixes, brain tunables |
| `tools/ecology_report.gd`, `tools/spawn_sim.gd` | roster by band/time/CR with gaps; director simulation and `perf=` measurements |
| `tests/test_monster_nav.gd` (+ `nav_maps.gd`), `test_monster_brains.gd`, `test_ecology.gd`, `test_monster_world.gd` | 190 checks |
| addon (`godot-srd-addon` a794bc2) | `SRDContent.make_npc`, `Combatant.senses`, `tests/test_make_npc.gd` (7 GUT tests) |

## Navigation

A node is a body's box at whole cells: left column L, feet row y, covering cw x ch cells (box
rounded up: Tiny 1x1, Small 1x2, Medium 2x3, Large 3x4, Huge 5x5, Gargantuan 7x7). Edges are
what `PlayerController` does with that body's MoveStats:

| Edge | How it is derived | Follower input |
|---|---|---|
| walk | next column standing; step-up up to `step_tiles` with headroom; snap down | `move_x` toward a carrot up to 4 nodes ahead |
| drop | walk off a ledge, first floor or water below (24 tiles max; cost grows past 4 tiles, the fall-damage height) | steer to the landing column (air control) |
| jump | **recorded**: for each body profile, the real controller is run on an empty world with scripted inputs (jump held 2/4/7/12 ticks, sideways from tick 0/3/6/9), every landing row crossed on the way down is kept with the cells its box swept (ascending cells must be free, descending cells free and not one-way); mirrored for the left. 200-216 arcs per profile, built in ~20 ms at spawn | align on the start node (within 0.2 tiles, slow), then replay the recorded inputs tick by tick; then settle |
| platform | down + jump through one-way tiles | down + jump once |
| ladder | ladder cell in the box's centre column (the controller's rule), ladder top rungs | up/down; leaves a rung only once past the row |
| cling | climbers (SRD climb speed): wall beside the box; up/down a wall, over its top | push into the wall + up |
| fly | 8 neighbours through open space (no corner cutting) | `move_x`, up/down |
| swim | 8 neighbours in liquid (centre column wet over half the box), for everyone | `move_x`, up/down/jump |

Diggers: a burrow speed (>= 20 ft: up to stone, hardness 2.0; less: soft tiles) or the
Tunnelling affix (soft tiles, hardness <= 0.6) may plan through solid cells at a cost;
`NavFollow` digs the next node's solid cells with `world.set_fg(x, y, AIR)` after
hardness / rate seconds (the host's TILE events and dressing checks follow as for any edit).

Bounded and budgeted: a search sees a 129 x 129 window around the start (WINDOW 64), expands at
most 1500 nodes (`NAV_MAX_EXPAND`) and returns a partial path to the nearest reachable node when
the goal is out of reach or outside. Searches are resumable; `MonstersSystem` runs the queue
round-robin within `NAV_BUDGET_US` = 800 us per tick (time-checked every expansion). Brains
replan every 3 s, when the goal moves 4 tiles (at most twice a second), at most once a second
without a path, after a failed plan only every 2 s; three unreachable plans in a row and it
loses interest and goes home. A tile change inside a path's bounds drops the path. Near and
in line (10 tiles, same row, clear line, on the floor) brains steer straight.

**Measured** (tests on hand-built maps, real bodies through the real controller): stairs, two-
high steps (jump), a 5-wide gap, out of a 5-deep pit (an 8-deep one is correctly unreachable
for a walker and walked out of by a climber), up one-way platforms, down through one, a 12-high
ladder shaft, a 3-high tunnel (Medium yes, Large no; Large through a 4-high one), a giant
spider up an 11-high wall, a giant bat through a winding cave, a swimmer to the bottom of a
pool, a tunneller through 12 columns of dirt (digging 36 tiles), a drop off a 6-high ledge, the
window's partial path, sliced = whole search.

**Generated caves** (1024x512 seed 11, 24 random pairs ~40 tiles apart and air-connected in the
caves band): **9/24 reached (38%)** for a Medium walker and 9/24 for a Large climber; every path
the search found was walked to the end by the real body (9/9). The misses are cramped, jagged
noise shafts a 2x3 (or 3x4) body cannot climb without digging. So "more often than not" is
**not met** on raw cave terrain; it is met for targets the planner can reach. Options for the
integration pass: let cave hunters dig (they already can with Tunnelling), wider worldgen
tunnels, or wall-jumps.

Limits: no ceiling walking (the controller has none: lurkers wait on walls or hover); swim
is approximate (centre column); a Large climber's mount over a wall top uses a fixed 0-2 row
search; profiles are cached per movement numbers (a static dictionary, host thread only).

## Brains

`MonsterBrain`, archetype from `habitats.json` `brain` (overridable per spawn). States: idle,
wander (around home), lurk, chase, flee, return. Tunables in `data/ecology/brains.json`.

| Archetype | Defining behaviour | Count in the table |
|---|---|---|
| bruiser | close and hit, short back-off (0.4 s) | 85 |
| skirmisher | hit and retreat 1.2 s at full speed | 29 |
| archer | keeps 7-14 tiles, ranged action; steps away or melees when crowded | 2 (+35% of mixed melee/ranged pack followers) |
| caster | keeps 6-12 tiles, ranged attacks (monster Spellcasting is not supported by combat) | 12 |
| heavy | slow (0.8), no back-off, breath/area save actions when ready and in range | 95 (dragons, giants, golems, breathers) |
| swarm | rushes, 0.2 s back-off | 16 |
| lurker | waits still (perch: ceiling, wall, floor, burrow) until prey is within 6 tiles or it is hit | 24 |
| flier | approaches from 4 tiles above, swoops, climbs away after a hit | 45 |
| ambusher | waits in water until prey is within 9 tiles | 22 |

Shared: senses every 0.3 s while chasing, 0.5 s when calm: combat's `sight.can_see` (light,
Darkvision, blindsight, truesight; NPCs' species senses) within 30 tiles, plus hearing a player
in combat within 20. Packmates within 28 tiles are alerted (a neutral herd defends itself).
Spacing: slot 0 goes straight in, odd slots aim for the far side (a different way round),
even slots stop a tile short. Leash 48 tiles from home, then return. Flee at 25% HP for rows
with `flee` (beasts, goblinoids, people; never undead, constructs, oozes, plants, elementals,
fiends, aberrations, dragons, celestials), for 6 s. Telegraphs: it stands still through
combat's wind-up and recovery, as the reference brain. Neutral creatures (65 rows: herd
animals, most plants, many fey and celestials) are never aggressive until attacked or
cornered (a player within 2.5 tiles for 2.5 s) and carry meta `friendly` (they do not block
rests). A Bond (`rules.bond(player, key) >= 1`, key `beast:<kind>` or `people:<culture>`)
keeps a creature friendly toward that player unless provoked. Calm brains think at 10 Hz;
brains with no player within 56 tiles think twice a second and stand still.

## Ecology (data/ecology/habitats.json)

One row per SRD slug (330): `biomes` (surface: meadow, forest, hills, swamp, desert, arctic,
coast; underground: caves, underdark), `bands` (sky, surface, caves, deeps, nadir), `time`,
`role` (pack, solitary, leader, boss), `pack` [min, max], `minion`, `leader_of`, `brain`,
`hostility`, `flee`, `spawn` (wild 200, lair 54, portal 46, people 23, none 7), `planes` for
extraplanar creatures (generic: lower, upper, elemental), `medium: water`, `perch`, `bond`, `w`.
Drafted by rule from type, size, speeds, senses and actions, then hand-corrected (notable:
aboleth nadir water lair-only; darkmantle caves ceilings, minion packs; wolves surface night
packs led by dire wolves or werewolves; dragons lair-only by colour and biome; fiends,
celestials and elementals only at the portal and in lairs, except the Material ones such as
gnolls, sahuagin, merfolk, gargoyles, giant eagles; peoples spawn as raider parties).
Worldgen has only `meadow` on the surface so far: `spawning.json` `biome_fallback` lets meadow
stand for meadow, forest and hills until more biomes exist.

`tools/ecology_report.gd` (kinds spawnable at night in the band's CR window): surface 98, sky
9, caves 69, deeps 41 (+7 in water), nadir 8 (+1). **Gaps**: the nadir (CR 8-17) has 1 kind at
CR 6-8 (cloaker), 5 at 9-11 (behir, clay and stone golems, fire giant, remorhaz), **none at
CR 12-14** and one at 15-17 (iron golem); the sky at night has 2 kinds at CR 1/2-1 and 1 at
CR 2-3. The SRD's high-CR Material creatures are mostly dragons and named bosses (lair-only)
and fiends (portal-only); filling the nadir means letting some deep lairs or planar creatures
roam, a design call.

## Ranks and affixes

| Rank | Hit points | Affixes | XP (meta `xp_mult`) | Look |
|---|---|---|---|---|
| minion | 1 (dies to any damaging hit that lands) | 0 | 0.25 | |
| standard | as written | 0 | 1 | |
| elite | maximum of the hit dice (ogre 8d10+24 = 104) | 1 | 2 | scale 1.12 |
| champion | double that | 2 | 4 | scale 1.3 |
| boss | as written (lair creatures), whatever combat supports of the kit | 0 | 6 | scale 1.15 |

Rank is set as Object meta `rank` and `xp_mult` (what the rules track reads; the multipliers
equal its `RANK_XP`, so Rules needs no call) and mirrored to `look.rank`, which the items
track reads for loot. Only rows marked `minion` spawn as minions. Affixes
(`data/ecology/affixes.json`; none touch attack bonus, AC or DCs):

| Id | Name | Effect |
|---|---|---|
| frenzied | Frenzied | `combat.set_pace(e, 1.6)`: what follows the wind-up is 1.6x faster; the telegraph is kept |
| shielded | Bubble-Warded | a ward of temporary hit points (6 x CR, at least 8), broken first; regrows 20%/s after 6 s out of combat |
| splitting | Mitotic | on death, two minions of its kind one size smaller (scale 0.75) |
| tunnelling | Tunnelling | plans and digs through soft tiles (dirt, grass) |
| lantern_eater | Lantern-Eater | eats a lit torch tile within 6 tiles every 1.5 s |
| tethered | Tethered | half of each hit it takes goes to the nearest packmate within 24 tiles |
| gilded | Gilded | sheds 1-6 coin per hit (`items.drop`), 60 at most |
| magnetic | Magpie | pulls loot on the ground within 10 tiles toward itself (the items system's drops) |
| howling | Howling | on first sighting calls 2-4 more of its kind from off-screen |
| thorned | Bramblehide | an attacker within 3 tiles takes 1d6 piercing (`combat.damage`) |
| skittering | Skittering | runs 1.35x faster |

## Spawn director (data/ecology/spawning.json)

| Band | Time | CR of a creature | CR budget alive | Most per pack |
|---|---|---|---|---|
| surface / sky | day | 0-1 | 3 | 1.5 |
| surface / sky | night | 0-3 | 7 (sky 6) | 4 |
| caves | any | 1/2-5 | 10 | 6 |
| deeps | any | 3-11 | 26 | 16 |
| nadir | any | 8-17 | 48 | 30 |

Cost of a monster = CR (CR 0 counts 1/8) x its rank's XP multiplier. Every 1.5 s, per player
group (players within 64 tiles of each other, chained, share one budget; others get their own):
up to 10 tries for a spot 40-62 tiles from a group member, standing (fliers lifted 8-14 tiles
into open sky on the surface), never inside any player's view rectangle (32 x 18 half-size plus
6), never within 50 tiles of a settlement site or 20 tiles of a campfire or bed. The pack: a
weighted pick from the roster (band, biome, time, CR window, at most the room left); a leader
pulls its `leader_of` followers; followers of minion-capable kinds are minions 60% of the
time, the rest roll ranks (surface 90/9/1 standard/elite/champion ... nadir 70/22/8).
Raiders: bandits (cultures.json `bandit` raider recipe) on the surface at night, 12% of
attempts; drow parties in the caves and deeps within 160 tiles of a deep road's end, 10%; each
member `make_npc(role, species, lineage)` with `look.people` like `human:raider`,
`elf:drow:scout` and Bond key `people:<culture>`. Caps: 24 per player, 120 in all. Despawn:
20 s with no player within 96 tiles and not in combat. One seeded RNG (world seed): the same
movements give the same spawns (tested).

`tools/spawn_sim.gd -- minutes=3` (1024x512 seed 4, player walking; CR alive / count every 15 s):

| Band | Packs / creatures in 3 min | Ranks | CR alive | Tick avg / p99 |
|---|---|---|---|---|
| surface day | 41 / 83 (42 despawned) | 51 standard, 28 minion, 4 elite | 2.9-3.0 with 11-25 creatures | 0.8 / 2.3 ms |
| surface night | 45 / 114, 7 bandit parties | 60 standard, 51 minion, 2 elite, 1 champion | 5-7 with 13-26 | 1.0 / 2.3 ms |
| caves | 5 / 9 | 8 standard, 1 minion | 10 with 9 | 0.4 / 0.4 ms |
| deeps | 10 / 18, 3 drow parties | 18 standard | 26 with 18 | 0.7 / 1.0 ms |
| nadir | 4 / 4 | 4 standard | 43 with 4 | 0.3 / 5.2 ms |

Examples: surface day "giant-hyena + 5 hyenas (4 minions)", "3 goblin warriors (1 minion)";
night "4 zombies (2 minions)", "3 giant spiders". The deeps and nadir fill with few, big
creatures (the budget is CR, and the nadir roster is thin, see Gaps).

## Lairs (first materialization)

`LairLink`, every second: a sim lair (`host.sim.lairs`) whose site is within 80 tiles (x and
y) of a player is materialized: exactly `SimLair.monsters` (slug -> count) at the site, one
pack, home at the site; the highest-CR member leads, as `boss` if the lair is apex or its CR is
5+. While materialized it is reconciled with the sim each second (a hunting pack left, it bred,
another lair moved in). A kill calls the new `WorldSim.lair_killed(site, slug, by)`: one fewer
in the sim; when the lair is empty with no pack out it is gone through the sim's own
`_lair_gone`, counted in `lairs_cleared`, with the chronicle line "adventurers cleared the
<what> at <lair>". Past 112 tiles survivors fold back (removed; the sim still counts them).
Nothing extra is saved: the sim is the truth. Tested: counts equal after materialize, a kill
written back, the sim saved and reloaded mid-way and the lair re-materialized from it, fold
back keeps the count, re-materialize equals it, killing all clears the lair with the line.

## Client (for the Interface track)

```gdscript
var mc := cw.system(HostSystem.MONSTERS) as MonstersClient
signal monster_info(id, info)   # info: {id, rank, slug, people, scale, flags (1 neutral, 2 lair, 4 leader),
                                #        affixes: [id], names: [shown name]}
signal monster_gone(id)
mc.info_of(id) -> Dictionary; mc.look_of(id) -> Dictionary
```

INFO (SYS kind 1) goes to a player for each monster entering its interest area (checked every
10 ticks), GONE (kind 2) when it is removed; layouts in `monsters_codec.gd`. On INFO for an
actor it already has (and when such an actor is added later) the client re-emits
`cw.actor_added(id, look)` with `slug` or `people`, `rank` and `scale`, so the existing view
rebuilds the right body. ENT_ADD names carry the affix names ("Gilded Frenzied Ogre").
What the UI should show: a rank badge on nameplates (minion small, elite/champion coloured,
boss bar), affix names under the name, neutral creatures in a calm colour, the leader of a
pack, champions are already scaled 1.3.

## Hooks outside the track (all additive)

- `core/combat/combat_system.gd`: `Actor.pace`, `set_pace(e, mult)` and `_paced()` (the
  timeline after the wind-up divided by pace); in `_after_damage`, before the 0 HP check, every
  other system with `on_combat_damage(e, dealt, src)` is called (misses too, dealt 0).
- `core/combat/combat_sight.gd`: `senses_tiles` uses `e.combatant.senses` when present (NPCs
  from make_npc keep their species' Darkvision).
- `core/sim/world_sim.gd`: `lair_killed(site_id, slug, by := "adventurers") -> bool`;
  `core/sim/sim_chronicle.gd`: the `lair_cleared_players` line and weight.
- `game/main.gd`: host option `spawns=0|1` (default: auto, on for generated worlds, which have
  depth bands, off for the fixed test world) and a `HOSTSTATS monsters:` line.
- `tools/net_smoke.sh`: `SPAWNS=1` variant (checks the director spawned).
- Addon (`godot-srd-addon` a794bc2, submodule bumped): `SRDContent.make_npc(role, species,
  lineage := "", id := 0)`, `NPC_LINEAGES`, `Combatant.senses` (filled by make_monster too).
- No changes to `world_host.gd`, `protocol.gd` or the endpoints.

## Performance

`tools/spawn_sim.gd -- perf=20,60,120 seconds=30` (caves, two players, hostile cave packs at
12-60 tiles, director off; this machine, headless, a GPU batch running):

| Monsters | Chasing | Tick avg | p99 | max | Plans/s | ms per plan | Nav ms/tick |
|---|---|---|---|---|---|---|---|
| 20 | 3 | 1.71 ms | 3.73 | 4.9 | 1.4 | 12.6 | 0.59 |
| 60 | 12 | **3.90 ms** | 8.14 | 11.2 | 2.4 | 10.5 | 0.90 |
| 120 | 43 | 7.51 ms | 13.4 | 21.3 | 3.8 | 5.1 | 0.89 |

Of the 60-monster tick, 1.73 ms is the same monsters without brains (controller steps,
combat, the system); brains about 1.3 ms; nav under 1 ms. Spikes: a new movement profile
records its jumps at spawn (~20 ms once per kind of body), the host LightEngine's first cold
chunk (combat's). Cuts made: calm brains at 10 Hz, distant ones at 2 Hz, sensing every 0.5 s
when calm, O(1) reach tests instead of `targets_in_reach`, cached line checks, time-bounded
search slices. Snapshot for a player seeing 30 monsters: 516 B per snapshot (6 + 17 x 30) at
15 Hz = 7.7 KB/s, plus INFO once per monster (~30 B) and VITALS/combat events on change.
Net smoke with the director on a dev world: 30 monsters, host tick avg 1.4 ms, SYS 4.9 KB.

## Tests and smokes

`godot --headless -s res://tools/run_tests.gd`: 2748 checks, ALL PASS. Addon GUT: 623 tests
passing (616 before). `tools/net_smoke.sh`: PASS; `FIGHT=1 SPAWN=goblin-warrior:2`: PASS
(killed 2); `SPAWNS=1 WORLD="gen=dev seed=3" SEE=`: PASS (30 spawned around the bots).

## Open issues

- **Needs playing**: how packs feel at the 0.5 s wind-up (skirmisher retreats, archer
  distance, flier swoops); minion volume vs XP; whether day surface CR 3 is too quiet and the
  deeps' few big monsters too static; every affix by hand (Tethered and Thorned numbers,
  Magpie stealing loot, Lantern-Eater eating player torches); lurkers' trigger radius.
- Cave reach rate 38% on raw noise caves (above).
- The nadir roster is thin (gaps above); the sky band is thin at night.
- Light preference: the director does not query light (it would build host light chunks);
  underground spots are dark anyway, the surface is lit by day.
- Water creatures never spawn yet (worldgen has no liquids); ambusher and swim nav are tested
  on a hand-built pool only.
- Lurkers wait on the floor or a wall (no ceiling walking in the controller); darkmantles and
  cloakers fly, so they hover.
- Monster Spellcasting, legendary actions and lair actions are combat's open items; bosses use
  what combat supports.
- Minions with resistance to the damage type take 0 from a 1-damage hit and survive it.
- `MonsterBrain` uses combat's `_targetable` (a private helper).

## After the integration pass

The seams this track left open were wired in [m2-integration.md](m2-integration.md); the public
surface it added here is listed in architecture.md, "M2 contracts / Integration".
