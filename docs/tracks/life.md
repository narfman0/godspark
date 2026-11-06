# Track: Life (M4 wave 1)

Branch `ws/life`. The sim's people in the world: who fights whom, standing with factions,
settlements and road parties materialized near players, their fights written back to the
sim. Design: [m4.md](../m4.md); contract: [architecture.md](../architecture.md), "M4
contracts / Life".

## What was built

| File | What |
|---|---|
| `core/life/life.gd` | `Life`: stance constants, `faction_of`, data access, `rng_for` (hash-seeded generators), `people_key` |
| `core/life/life_system.gd` | `LifeSystem` (HostSystem.LIFE): stance, standing, death and damage hooks, client messages, cheats |
| `core/life/life_town.gd` | `LifeTown`: settlements as guards and townsfolk on a daily round |
| `core/life/life_road.gd` | `LifeRoad`: parties on the roads, real-time ambushes and raids, loot drops |
| `core/life/life_brain.gd` | `LifeBrain extends MonsterBrain`: posts, fighters and civilians |
| `core/life/life_codec.gd`, `life_client.gd` | SYS messages (JSON payloads) and the client mirror |
| `data/life/standing.json`, `people.json` | standing numbers; what materializes, caps, round, break fractions |
| `tools/life_day.gd` | a day in the life (and `perf=1`) |
| `tests/test_life.gd` | 90 checks: stance, standing, towns, roads, dice |

## Stance (who fights whom)

`life.stance(a, b)` is symmetric and cached per tick:

1. Players among themselves, and people of one faction: FRIENDLY.
2. A grudge: HOSTILE. An unprovoked attack on a faction's person (one that was not already
   a foe) makes that whole faction hostile to the attacker for `grudge_s` (60 s); a monster
   brain's `provoked` (it was hit, or a neutral beast was cornered) counts the same way.
3. Wild creatures (lairs, the spawn director, sim monster packs; faction "wild"): HOSTILE to
   everything not wild unless the ecology row is `neutral` (NEUTRAL) or the player has the
   creature's Bond (`rules.bond(player, key) >= 1`: FRIENDLY). Wild among wild: NEUTRAL.
4. A player and a faction's people, by standing: `<= hostile_at` (-40) HOSTILE, `>=
   friendly_at` (30) FRIENDLY, else NEUTRAL. Raiders (members of raid and army parties)
   spare a player only from `raiders_spare_at` (60).
5. Two factions, as the sim fights: HOSTILE at war; HOSTILE when one side is out raiding and
   `SimConflict._hostile(raiding = true)` says so, or the raider's party targets the other
   faction's settlement (or route); FRIENDLY at relations >= 40; else NEUTRAL. Peoples not
   at war never fight just for bad relations (the sim never makes them).

`combat.hostile(x, y)` asks Life when it is installed (`stance == HOSTILE`), so
`nearest_foe`, `targets_in_reach`, melee arcs, projectiles, spells and the ally checks all
follow it. `MonsterBrain` senses every creature (not only players) with Life and picks foes
through `is_foe` (provoked, or `hostile_to` for players, then Life). Without Life
everything is exactly as before (players vs monsters; suite and arena unchanged).

**Friendly fire with Life:** sweeps and cleave touch foes only; harmful areas (damage or a
save) skip FRIENDLY and NEUTRAL creatures and the caster. A player's blow, arrow or foe spell
**aimed** at a non-hostile creature (the aim point inside its box, no foe there, and the
player not in the middle of a fight with foes) is allowed: it hits, the victim's faction
holds a grudge, standing drops (`attack_member`), guards within 40 tiles take the attacker
on, townsfolk within 30 run. Without Life none of this exists.

## Standing

`life.standing(player_id, faction) -> -100..100` (faction = sim faction id as a string),
saved in the player record (`save_player`), mirrored to the owner. A Bond with the faction's
people (`people:<culture>`) raises it to `bond_floor` (30). Changes (data/life/standing.json):

| Event | Change |
|---|---|
| attack one of its people unprovoked | -5 (once per grudge) |
| kill one of its people / a guard or escort | -20 / -30 (raiders exempt) |
| kill a creature its shown people within 80 tiles count as a foe | +3 (+4 for raiders) |
| a raid wiped out on the road by players | +15 to each faction it was going for |
| drive off a raid at a watched town (players among the killers) | +15 |
| save a caravan from a real-time ambush | +10 |
| kill a creature of a lair that preyed on it (grievance, or hunts its routes) | +1, clearing the lair +12 once |

`life.add_standing(id, faction, n, why)` is the Deals entry point.

## What materializes and how it folds back

**Settlements** (`LifeTown`): within 80 tiles (x and y) of any player, kept to 112. Guards are
the garrison: exactly `garrison()` up to 8, else a largest-remainder sample of the culture's
guard recipe. Townsfolk: 4 / 8 / 16 / 24 by tier (never more than the civilians), the first
by tier being keeper, smith, merchant, priest...; SRD blocks through `make_npc(role, species,
lineage)` (priest-acolyte for priests, the culture's `people` block otherwise; monstrous
cultures their people block), `look.people` like `human:guard`, `elf:drow:guard`,
`human:commoner:f`. Names from the culture's syllables, seeded by (world seed, site, slot,
generation). Meta: `sim {kind: settlement, id, role, slot}`, `faction`, `talk`, `friendly`.
Posts on the real place: each role at its buildings' anchors (smith at the forge, merchants
at the stalls, keeper, priest; guards at the gate anchors), a second person a step aside,
anyone beyond twice the anchors spread along the `street`; a spot that would put someone on
a roof is refused (they stay on the anchor's floor). At night and when frightened people go
indoors: the middle of a home's ground floor, through its door on the street. Only worlds
without places use the old spread over the site (keeping 24 tiles around the centre clear). Round: work 6-18, the
square at dusk 18-21, home door at night; guards at their posts, with meta `torch` and
`look.light` at night (combat sight counts them as carried light). Civilians run for their
door from a foe or a nearby fight and calm after 8 s; fighters run to fights. While shown,
the sim settlement is `watched`; each scan the shown people are reconciled with the sim
(soldiers away with a caravan go off duty, growth adds people).

**Parties** (`LifeRoad`): a party whose point (route id + fraction through
`Places.route_path`, interpolated, on its feet cells; a straight line between the sites
when no path is stored) is within 80 tiles. On `rough` routes the same cells are used; the
people walk them with monster nav as far as they can and are put back beside the party when
40 tiles behind. Between the sim's hourly steps the point moves on at the party's pace
(display only), so people walk the road. Members up to 12 (sampled when bigger); the culture's people
block among `people` are civilians (drovers, migrants), the rest fighters by kind (escort,
raider, guard, soldier, monster); a caravan shows up to 2 draft horses as its wagons (meta
`look.wagon`; a killed wagon is one fewer `wagons`). **Lockstep**: the sim keeps moving the
party at its pace and the actors' posts follow its point, so watching changes nothing; only
when its people fight a foe is the party `frozen` (no movement, timers or arrival). A raid
(or monster pack) within 48 tiles of the watched town it is going for starts the real-time
raid at once (it does not wait for the sim's arrival step). Townsfolk who die are not
replaced until the town has been quiet for 32 s.
A hold with no blows for `stall_s` (45 s) lets go.

**Write-back**: every death is written at once (`WorldSim.party_member_killed`,
`settlement_person_killed`), so fold-back is just removing the actors (and clearing
`watched` / `frozen`); a save mid-way needs nothing extra (the sim is the truth; after a load
Life folds everything and shows it again). Real-time fights end by the sim's own break
fractions and its own outcome code:

- a raid (or monster pack) arriving at a watched settlement is handed over (`frozen` by the
  sim at `_arrive`); raiders lose at 40% losses, defenders break at 35% of the garrison
  killed; then `SimConflict.raid_outcome` / `pack_outcome` (plunder, relations, chronicle,
  home). No blows for 45 s: the sim's `_raid_settlement` decides.
- raiders and a caravan, migrants or settlers coming to blows: an ambush; raiders give up at
  50%, victims at 60% or no fighters left; then `SimConflict.ambush_outcome` (loot taken into
  the raiders' cargo, captives, relations, chronicle).
- a raid wiped out on the road never happens; the chronicle says `raid_repelled`.
- a laden raider (raid/army party with cargo or coin) that dies drops its share as items
  (`items.drop`): `trade:<good>` when Items has such rows, else their worth in coin (Items has
  no trade-good rows yet).

## Travel pace (orchestrator's decision, after the merge with Places and Traversal)

Parties move at an on-screen pace, watched or not: a wagon (caravans, settlers) 1.5 tiles a
real second, people on foot (raids, patrols, armies, migrants, expeditions, monster packs)
2.5; a game hour is K.DAY_SECONDS / 24 = 50 s, so a caravan covers 75 route tiles a game hour
and a trip between neighbouring towns takes a few real minutes. In the sim:
`WorldSim.TRAVEL_TPS`, `route_travel_h` (route tiles / pace), `leg_hours(kind, rid)`;
`PARTY_H` is 1 (was 6). Planning keeps the old strategic distances (`route_hours`: reach,
wagon costs, risk), so who trades with and raids whom is unchanged. Ambushes are checked
every hour; patrol clashes and lair hunts every 6 hours as before, lair hunts scaled by the
trip's exposure (`route_hours / leg hours`) so a trip is as dangerous as it was.

`run_history.gd -- seeds=1..30 years=200 sites=24`, per world (before: docs/tracks/sim.md;
after: this change):

| | before | after |
|---|---|---|
| caravans | 5981 | 5956 |
| ambushes | 27 | 17 |
| settlement raids | 127 | 110 |
| wars | 5.7 | 6.3 |
| conquests / sacks | 0.9 / 8.1 | 1.4 / 8.9 |
| foundings / fallen | 6.1 / 5.4 | 5.7 / 4.9 |
| lairs cleared | 17.3 | 18.6 |
| mean final/initial pop | 1.98 | 1.89 |
| food imported / migration after famines | 45% / 75% | 40% / 78% |

Health invariants unchanged (no negative books, 0 collapsed, 0 exploded, 30/30 grew and
declined, 29/30 trade and raids, 30/30 distinct). Sweep time 199 s -> 214 s; the sim's
"strategic day under 4 ms" test passes with little margin (hourly party ticks). Not
destabilising; ambushes fall by a third (caravans spend far less time on the road).

## Sim changes (all additive except the pace; none touch the sim's generator)

- `SimParty.watched`, `SimParty.frozen`, `SimSettlement.watched`: transient (not saved).
- `SimConflict.tick_parties`: skips frozen parties. `_arrive`: a raid (settlement mode) or a
  monster pack arriving at a watched settlement is frozen and left to real time
  (`_handed_off`). `_encounters`: patrol clashes, ambushes and lair hunts involving a watched
  party are skipped **after** their roll (the generator advances exactly as unwatched).
- `_raid_settlement`, `_pack_attack`, `_ambush`: the part after the fight moved into
  `raid_outcome`, `pack_outcome`, `ambush_outcome` (same code, same order of rolls).
- `WorldSim.party_member_killed(pid, slug, wipe := true)`, `settlement_person_killed(sid,
  soldier)`, `party_take_cargo(pid, good, n)`.
- `SimChronicle`: `slain_by_players`, `raid_repelled` lines.

Sweep `run_history.gd -- seeds=1..6 years=100 sites=20` before and after: identical output
(every per-seed line and every statistic).

## Per-entity dice

People, names and posts come from `Life.rng_for([world seed, kind, id, slot, generation])`;
generations are saved with the world (`save_world`). Real-time fights use the host's combat
dice. Test: two hosts, same seed, one with a player touring towns and two caravans for a game
week (standing 100 with everyone, director and lairs off): `sim.rng.state` and `to_dict()`
identical.

## Client surface (Interface, Deals)

```gdscript
var lc := cw.system(HostSystem.LIFE) as LifeClient
signal standing_changed(faction: String, value: int, why: String)
signal factions_changed(); signal person_added(id, info); signal person_gone(id)
lc.factions            # {id: {id, name, culture, alive, standing}}
lc.standing(faction) -> int
lc.person(id) -> {id, role, kind (settlement | party), of (site or party id), faction, talk, name}
lc.is_person(id); lc.people_at(site_id) -> Array
```

SYS kinds (JSON payloads): FACTIONS 1 (on join and when the sim's factions change),
STANDING 2 (owner only), PEOPLE 3 (all players, batched per tick; the full list on join),
GONE 4. No protocol change.

Host: `life.stance`, `hostile`, `faction_of`, `standing`, `add_standing`, `actors_at(site)`,
`actors_of(party)`, `cheat_party(kind, from, to, frac, n)`, `schedule(kind, after_s, to)`,
`summary()`, `enabled`. Host options: `life=0`, `life_raid=S`, `life_caravan=S`; HOSTSTATS
`life:` line. Smoke `LIFE=1`.

## Limits and performance

Caps: 8 guards and 24 townsfolk per settlement, 12 members and 2 wagons per party. Calm
fighters think at 10 Hz (MonsterBrain), calm civilians at their post at 2 Hz with no nav;
Life's people never use the distant slow think (they exist only near players). Scans once a
second.

`tools/life_day.gd -- seed=3 perf=1` (headless, this machine): 59 actors (a city: 24
townsfolk + 8 guards, a caravan of 12 + a wagon, a raid of 10 down to 5), two players,
1800 ticks: **tick avg 3.34 ms, p99 9.13 ms, max 10.7 ms** (budget 33 ms). Snapshot estimate
for a player in that town: 60 entities, about 1 KB per snapshot (6 + 17 B each). Net smoke
`LIFE=1`: host tick avg 1.9 ms, p99 21 ms (the raid's first spawns record jump profiles).

## A day in the life (seed 5, excerpt)

```
== seed 5: Calwick (human, village, the Garfield Compact) and Hazadek; Day 0, 08:00
  books before: Calwick pop 599 (workers 361, dependants 209, soldiers 29), food 7106, coin 1198
  08:24  Calwick: 8 guard, 1 keeper, 1 merchant, 1 priest, 1 smith, 4 townsfolk; townsfolk 8 at work
  [cheat] a caravan from Hazadek is on the road
  09:24  ... | NEW caravan 1 of the Deepforge of Hazmor: 8 of 8 shown with 1 wagon(s), travelling, cargo food 100
  18:24  ... townsfolk 8 in the square | caravan 1: going home
  [cheat] raiders from Hazadek are near
  20:24  ... townsfolk 3 in the square, 5 running | NEW raid 2: 2 of 2 shown, fighting | 4 party_deaths, 12 town_deaths
      chronicle: first caravan from Hazadek (the Deepforge of Hazmor) reaches Calwick with food
  01:24  ... townsfolk 8 at home | 6 party_deaths, 15 town_deaths
      chronicle: dwarven raiders from Hazadek were cut down on their way to Calwick by defenders
  books after: Calwick pop 584 (workers 353, dependants 209, soldiers 22), food 7206, coin 1117
  real-time deaths written back: town 15, parties 6; audit: []
```

Population 599 -> 584 is the 15 deaths fought in real time; food +100 and coin -81 are the
caravan's sale.

## Deviations from architecture.md

- Positions are lockstep (the sim moves watched parties; actors follow) rather than "the sim
  takes position from the actors": the sim's travel pace is about 0.04 tiles per real second
  (24 game days per world width, a game hour is 50 s), so caravans on screen barely move; a
  party is held only while it fights. Losses are written back at once, not on fold-back.
- Contract constants are `Life.HOSTILE` etc. (class `Life`), the system is `LifeSystem`.
- Combat edits beyond the predicate: `_aimed` (deliberate attacks on bystanders), the
  projectile record carries its `aim`, areas spare non-foes with Life; `combat_sight` counts
  entities with meta `torch` as carried light; `CombatClient.fight_step` skips Life's
  people. `MonstersSystem.spawn` takes `opts.brain_obj`.

## Open issues

- Rough routes: people may not keep up with the party's point (nav), and are put back.
- A raid that cannot reach the town stalls and goes back to the sim after 45 s.
- Items has no trade-good rows: dropped cargo is coin. Returned cargo is not yet a deed.
- `friendly` meta is set on town people regardless of standing (a hostile town does not
  block rests). Hostile-by-standing townsfolk only flee.
- View: guards' torches are lit by the view presenter at night (a carried light per actor
  whose look has `light: torch`, from Life's PEOPLE info through `LifeClient.decorate_look`);
  a wagon is a draft horse with a primitive cart (box, canvas, two wheels) drawn by
  `WorldView`; no cart model was fetched.
- `raid` chronicle `killed` counts deaths after arrival only (fights at the gate before the
  sim's arrival tick are in `raid_repelled` or not at all).
- Net smoke: in a peopled spawn town the bots' place step is flaky (people walk over the
  cells they pick); the `ALL=1` variant runs with `places=0` (other variants still place).
- Not judged by eye: no screenshot of a town or caravan was taken.

## Screenshots (tools/life_shot.gd through tools/soft_godot.sh)

`/tmp/claude-1000/godspark-life/`: `day.png` (a halfling town by day: people at the market
stalls, homes and an upper floor), `night.png` and `night_guard.png` (townsfolk indoors,
guards in the gate tower and at the gate), `caravan.png` (escorts, drovers and the wagon on
the ramp out of town), `raid.png` (raiders reaching the town; a fight was under way).
Checked by eye: no one inside walls; a guard on a roof and a crowd of guards on one tower
cell were fixed (people stay on their anchor's floor; extras go along the street).
