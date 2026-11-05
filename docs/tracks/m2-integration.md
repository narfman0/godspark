# Track: M2 integration

The pass that made the five M2 tracks (rules, combat, items, monsters, interface) one game.
Branch `ws/m2-integration`, cut from main 947f933; main's play-session fixes (death pose,
no long-rest limit) merged in. One commit per item.

## 1. End-to-end test and the ALL smoke

`tests/test_m2_e2e.gd`: every system over the loopback on a generated world (1024x512 seed 5,
a walled arena at the surface). A fighter and a wizard fight a ranked goblin pack spawned
through `SpawnDirector.spawn_pack` (champion, standard, two minions) with attack and spell
intents; both clients see the swings, damage, every member reach 0 HP and be removed; XP and
levels match host and clients; loot is picked up; a +2 longsword equipped through the client
changes the host's to-hit and the next roll uses it; a ring bonds at a campfire (AC +1); a
spark kindled at a shrine gives identical MoveStats on host and client; a short rest on Hit
Point Dice; both sleep and the night passes; the wizard is downed by a goblin, hit while down
(one failed save), cannot dig, place, attack, cast or drink, and is revived; every mirror
(item 4) is checked; then the players leave, the world is saved, loaded into a new host,
both rejoin, and level, XP, inventory, equipment, bonds, sparks, slots left, deeds, knacks,
bed, HP, AC, to-hit, prefs and reach all came back. 129 checks.

`tools/net_smoke.sh` `ALL=1`: a dedicated host on `gen=dev seed=3` with the director on,
`cheats xp=10 pack=goblin-warrior`; both bots fight (kills and XP), regroup at the join
point, then run the whole rules scenario (rests, beds, downed, revive, death, respawn at the
bed, rejoin with the level). Bots fight back when monsters break a rest.

Integration bugs it found (all fixed in commit 1 unless noted):

| Bug | Fix |
|---|---|
| A hit on a downed player did nothing (no failed death save) | combat calls `rules.player_dropped(e, crit)` for every landed hit at 0 HP |
| A downed player could place, dig, drink, kindle, bond, pick up | `HostSystem/ClientSystem.allow_edit`, `Reason.UNABLE`; items refuse while down |
| Potions bypassed `rules.heal`; healing spells could not even target a downed ally (item 3) | one healing path; ally spells reach the downed |
| Spell slots spent in combat never reached `Character.slots_left` before a save | `Character.capture` copies slots and uses; rules captures every 15 ticks |
| Saved HP capped at the gear-less max (CON gear lost HP on save, load and level) | `capture`, `make_combatant`, `gain_level` no longer cap at `max_hp()` |
| Loot one tile below the feet was out of pickup reach | pickup measured from the body's box (1.25 tiles) |
| The director refilled a cleared area every 1.5 s: no rest was possible near the spawn | a lull after kills, no new packs while someone rests |
| `rules.refresh` rebuilt with the class's default weapon (a greataxe became a longsword after a level-up) (item 3) | it ends with `items.outfit` |
| Remote monsters drew as capsules (item 2) | protocol 7, see below |

## 2. Monsters look right on every client

The cause: INFO (rank, slug) reaches a chunk further than ENT_ADD, so a joining client usually
had INFO first. `add_remote` emitted the plain look; `MonstersClient` answered inside that
emission with the full look; the view built the model; then the outer emission reached the
view and rebuilt a capsule. Debug-spawned monsters (`spawn=`) never had INFO at all.

Fix: protocol 7, ENT_ADD carries the compact look (slug or `player:<class>`, people key, rank,
scale). `ClientSystem.decorate_look` lets a system fill gaps before `actor_added`; the
monsters client re-adds an actor only when INFO says something its look lacks. The own body
is drawn by class once the sheet names it. Nameplates show affix names, not ids.
`tests/test_m2_looks.gd` checks what a view connected after the systems holds.

## 3. Wiring

Reach and dig speed (`Items.edit_numbers`) on `HostEntity` and `ClientWorld` (a Mole III dig is
predicted to the step); Quickhand shortens recovery; Surefoot shrinks pushes; Featherfall's
new `fall_resist` (0.5/0.75/1.0) cuts fall damage; Steady wins back a cast slowdown that is
1.0 in data (none). Host-enforced movement limits from conditions (`move_limits`; speed 0 is
anchored). `WorldHost.teleport`. `tests/test_m2_wiring.gd` (42 checks).

## 4. Mirrors

DEEDS (rate-limited), SUMMARY (`SheetSummary.of`: the host's AC and parts, attacks, saves,
skills, features, resistances, tools, languages, speed; the client's stand-in Character and
its footers are gone), temporary HP in combat STATUS (HUD bar), REFUSED (attack or cast, with
the reason, a short toast), quick spells stored with the character (`Character.prefs`), the
hotbar selection already was. Knack card footers wrap inside their box; beasts are plural.

From the first play session (coordinator): hotbar slot 1 is the attack slot (starts selected
and empty, shows the wielded weapon, loot never lands in it; older saves migrate), and a
controls hint fades after the first attack.

## 5. Balance (data only; no stat block, attack bonus, AC or DC touched)

Arena, level 1, 20 seeds, wins (casters cast their cantrip and kite). Before: no potions;
after: `potions=2` (the kit's two); without them the after rows are 85/50/85/95,
100/75/50/95, 75/50/100/100 (fighter/rogue/wizard/cleric).

| Before: packs the director made by day | fighter | rogue | wizard | cleric |
|---|---|---|---|---|
| goblin-warrior x3 | 50% | 10% | 55% | 65% |
| 2 goblin warriors + 1 minion | 70% | 15% | 70% | 85% |
| giant hyena + hyena + 4 hyena minions (melee only) | 35% | 5% | 0% | 0% |
| giant spider (CR 1) (melee only) | 55% | 35% | 5% | 35% |

| After: packs near the spawn by day | fighter | rogue | wizard | cleric |
|---|---|---|---|---|
| goblin warrior + 2 minions | 90% | 70% | 90% | 95% |
| hyena + 3 hyena minions | 100% | 85% | 85% | 95% |
| goblin-warrior x4 minions | 90% | 65% | 100% | 100% |
| (still hard, now kept out near the spawn: 2 wolves) | 95% | 80% | 40% | 70% |

Director tables (`spawning.json`): a `ramp` near surface and sky settlements, blended out
between 120 and 480 tiles: by day budget 1.5 CR alive, 0.45 per pack, nothing over CR 1/4, 90%
minion followers, no elites or champions; by night 2.0 / 1.0 / CR 1/2 / 75%. Lull after kills
(`lull_s`): surface 10 s by day, 8 at night, caves 10, deeps 8, nadir 6. Settlement safe radius
50 -> 36. The nadir's missing CR 12-14: `promote` makes half its packs deeps creatures of CR
5-11 as elites (65%) and champions (35%).

Spawn sim, surface by day: before (from a third of the width, 3 min walking) 30 packs, 51
creatures, 36 standard / 13 minion / 2 elite, CR alive ~3, CR 1 solos (giant spider, tiger),
6-strong hyena packs; after (from the spawn settlement, 6 min, `kill=hunt`) 22 packs, 49
creatures, 33 standard / 16 minion, none over CR 1/4.

Healing potions (per 2000 surface kills, `loot_sim`): goblin warrior 122 -> 279, minion 8 ->
60, beasts (hyena, wolf) 27 -> 177. A separate `healing` chance by band and rank, rolled
last.

XP: kill rates measured with `spawn_sim kill=hunt from=settlement` (a hunter killing the
oldest monster at least 10 s old every 2.5 s): surface day 4.7 kills/min, 80 stat-block XP/min;
surface night 9.2, 222; caves 15.0, 2667; deeps 15.8, 7948; nadir 12.7, 56767. The deep rates
are capped by the hunter's pace, so `xp_pacing.gd -- measured` scales them to an assumed fight
length (caves 5 s, deeps 10 s, nadir 20 s). `XP_SCALE` 15 -> 8:

| | target | assumed table at 15 | measured at 15 | measured at 8 (chosen) | best single fit, 24 |
|---|---|---|---|---|---|
| levels 2-5 (min each) | 3-6 | 2.9-4.8 | 8.8-14.1 | 4.7-7.5 | 14-23 |
| level 50 | ~20 | 23 | 14 | 7.6 | 23 |
| the 90s | ~60 | 58 | 11 | 5.8 | 18 |
| to level 100 | ~40 h | 42 h | 18 h | 9.6 h | 29 h |

No single scale fits: the director's XP supply grows with depth faster than the SRD's XP
thresholds. 8 keeps the first levels on target; the deep bands need their own divisor
(docs/todo.md).

## 6. Cave navigation

Worldgen stage `cave_steps` (after `caves`, no RNG): three passes in the caves band open slots
under 3 tall or 2 wide; every air run taller than 5 against a real wall (rock beside 80% of
it) gets a ladder, ladders 4 columns apart. `tools/cave_nav.gd` (the monsters track's cave nav
test over seeds 3, 5, 7, 11, 13; 24 air-connected pairs ~40 tiles apart each):

| | before | after |
|---|---|---|
| Medium walker | 42/120 (35%) | 59/120 (49%) |
| Large climber | 40/120 (33%) | 50/120 (42%) |

Not a clear majority: the misses left are sealed pockets and 30-40-row climbs through rock.
Worldgen, dev size: about +156 ms (769 ms in all). No golden hashes exist; `test_worldgen` is
green.

## 7. The scripted slice

`UiTour.slice()` (and 08b): a ranked pack through the director's path, the fight, a corpse a
second after a death, loot, a level and a Knack, a found sword equipped, a cave by torchlight,
a wolf in the dark. Fixes from looking: a player at 0 HP now holds the death pose however it
got there; condition badges (Unconscious) clear when a player gets up; open caverns no longer
grow walls of ladders.

## Numbers

| What | Measured |
|---|---|
| Tests | 3070+ checks, ALL PASS (2863 before) |
| Host tick, ALL smoke (2 bots, director on, dev world) | avg 1.0-1.2 ms, p99 2.5-3.0 ms |
| Host tick, 60 monsters (`spawn_sim perf=60 seconds=30`) | PERF60 |
| Movement traces (nine scenarios) | core/entity untouched since 947f933; trace output identical |

## Deviations and notes

- Protocol is 7 (ENT_ADD look). Rules SYS kinds 8-10 and 72, combat 19 are new.
- `tempo_move` in data/combat.json is 1.0 (no slowdown while swinging or casting), so Steady
  does nothing until someone decides a cast should slow you.
- Monster brains still do not attack downed players.
- The ALL smoke bots hit rarely on uneven ground (a few damage events in 20-70 swings).
