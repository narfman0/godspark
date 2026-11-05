# Track: M2 base

The shared base the three M2 tracks (rules, combat, items and sparks) build on. The exact
API is in [architecture.md](../architecture.md), "M2 contracts".

## What was built

| File | What |
|---|---|
| `core/host/host_system.gd`, `client_system.gd` | `HostSystem` / `ClientSystem`: one per feature area, no-op hooks |
| `core/host/systems.gd` | `Systems`: fixed script paths per system id; whatever exists is installed by `NetSession` |
| `core/host/world_host.gd` | `add_system`, `system`, `send_sys`, `send_sys_near`, `receive_sys`; per-player and world save of systems; characters on join; `add_srd_monster`; shared `srd`; `Dice.rng` installed every tick |
| `core/host/host_entity.gd` | `character`, `combatant`, `vitals()` |
| `core/host/client_world.gd` | systems, `send_sys`, own `hp` / `max_hp`, remote hp, `apply_vitals`, `vitals_changed` |
| `core/rules/level_track.gd` | `LevelTrack`: the 100-level map, rewards, XP, hit points |
| `core/rules/character.gd` | `Character`: record, default builds, `make_combatant`, `gain_level`, round trip |
| `net/protocol.gd` | protocol 6: SYS, VITALS, class in HELLO, hit points in ENT_ADD |
| `net/host_endpoint.gd`, `client_endpoint.gd`, `net_session.gd`, `bot_client.gd` | routing, VITALS per peer, class option, bot vitals line |
| `game/main.gd`, `presenter.gd`, `log_presenter.gd` | `class=`, `spawn=SLUG[:N]`, `actor_vitals` |
| `tests/echo_system.gd` | the example system pair (tests only) |
| `tests/test_systems.gd`, `test_level_track.gd`, `test_character.gd` | new tests; `test_protocol.gd` extended |
| `tools/net_smoke.sh` | spawns `SPAWN` (default `goblin-warrior:1`); bot1 must report it with `SEE` (default `Goblin Warrior monster 10/10`) |

## Decisions and deviations from the contract

- **Plug-in by path.** Tracks never edit boot code: `Systems.HOST` / `CLIENT` name
  `core/rules/rules_system.gd`, `core/combat/combat_system.gd`,
  `core/items/items_system.gd`, `core/monsters/monsters_system.gd` and the matching
  `*_client.gd`. A script there whose `new()` takes no arguments is installed.
- **Hit points travel as ENT_ADD plus VITALS**, not in snapshots: snapshots are unreliable
  and the own player is not in them. VITALS is reliable and only carries changes.
- **Class on join** is a HELLO field (`class=` option); a saved character wins over it.
- `LevelTrack.Reward` has `EPIC_BOON` for level 100. Levels 96-100 run one more band past
  class level 20 with the last SRD gaps (50000 XP, one more hit point gain).
- `Character.create` takes an optional trailing `srd` (to answer class level 1 choices);
  `move_stats` takes the combatant (the record holds no combatant). Added `answer_choice`,
  `pending_choices`, `auto_choices`, `capture`, `resolved`, `max_hp`, `hit_dice_max`.
- `send_sys` returns false and warns for payloads over 32 KiB.

## Numbers

| What | Measured |
|---|---|
| `SRDContent.new()` | 17-19 ms, once per process (`WorldHost.warm_srd()` in `start_host`, before the host thread) |
| `Character.create` + level-1 choices | 0.2-0.6 ms |
| `make_combatant` | 0.15-0.3 ms (levels 1-50) |
| `auto_choices` from 1 to 50 | 1.2 ms fighter/rogue, 8-11 ms cleric/wizard (spell lists) |
| SNAPSHOT per entity | 17 B before, 17 B after |
| ENT_ADD | 24 + name before, 28 + name after |
| VITALS | 2 + 8 per changed entity, only on change |
| Smoke run (2 bots, 1 goblin) | VITALS 4 msgs / 40 B in total; host tick avg 193 us |
| Tests | 1702 checks (1451 before) |

## Open issues

- The client mirror of the character (rules track) and the hit point bar (interface) do
  not exist yet; the own player's hit points are on `cw.hp` / `cw.max_hp`.
- `ItemEffects.apply` changes max hit points by `con_delta * class level`; with the level
  track the items track must recompute max HP from `LevelTrack.max_hp` after gear.
- Species and background are stored but not applied (the addon takes neither).
- `Dice.rng` is still a process-wide static: two ticking hosts in one process (tests only)
  take turns installing theirs.
- Brainless SRD monsters do not fall (only bodies with a brain are stepped).
