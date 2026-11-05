# Track E: the strategic world simulation

Branch `ws/sim`. Owns `core/sim/`, `data/sim/`, `tools/run_history.gd`, `tests/test_sim_*.gd`.
A headless, seeded, deterministic simulation of a strip of sites joined by routes.
Settlements grow and shrink with food, trade by caravan, get raided, go to war, fall to
ruin and found daughter towns. Monster lairs hunt travellers. It produces a chronicle.
There are no graphics; judge it by `tools/run_history.gd`.

## API as built

```gdscript
WorldSim.from_meta(meta, seed) -> WorldSim     # sites/routes per architecture.md Track A
WorldSim.synthetic(n_sites, seed) -> WorldSim  # same schema, made up (tests, tools)
sim.step(hours)                                # any whole number of hours; slicing is exact
sim.to_dict() / WorldSim.from_dict(d)          # plain data; exact round trip
sim.chronicle                                  # [{t, kind, ...names and ints}]
sim.describe(event) -> String                  # "Year 12, spring: ..."
sim.entities_near(x0, x1) -> {settlements, lairs, parties}
sim.party_position(p) -> {route, frac, site}   # frac measured from route.a
sim.audit() -> Array[String]                   # invariant violations, [] when healthy
sim.total_pop(), sim.stats (counters), sim.year(), sim.season()
SimCombat.resolve(rng, side_a, side_b, opts) -> {winner, rounds, a_dead, b_dead, a_left, b_left}
SimCombat.odds(a, b, b_ac, b_hp) -> float
SimHealth.run(seed, years, sites) -> Dictionary   # sweep statistics
```

Files: `world_sim.gd` (state, graph, paths, stepping, queries, serialization),
`sim_economy.gd` (production, prices, population, caravans, migration, founding),
`sim_conflict.gd` (party movement, encounters, raids, patrols, lairs, expeditions, war,
sieges, outlaws, tribute), `sim_combat.gd`, `sim_chronicle.gd`, `sim_data.gd` (tables and
an SRD monster profile cache), `sim_names.gd`, `sim_health.gd`, and plain state classes
`SimSettlement`, `SimFaction`, `SimLair`, `SimParty`.

Data: `data/sim/goods.json` (food, timber, ore, tools, luxuries), `biomes.json` (capacity
per biome, band fallbacks, includes worldgen's `caves` and `underdark`), `cultures.json`,
`lairs.json`, `names.json`.

## The model

**Time.** Hours. A year is 360 days, four 90-day seasons. Parties move every 6 hours; the
economy and settlement decisions run every 5 days (an "econ tick"); factions decide monthly;
weather, lair growth, founding, outlaws and tribute are yearly. `step()` jumps from boundary
to boundary, so stepping by 1 hour or by 200 years gives identical results (tested).

**Space.** Sites sit along x. Route classes: road (both ends on the surface), deep road
(both underground), link (one end each; worldgen's deep-to-surface `deep_road`). Travel
time = route length / world width x 24 days, divided by the party's speed. Each culture
names which classes its caravans and its raiders use: humans only roads, drow deep roads
and links (and roads when raiding), dwarves all three. Sites without routes get a "trail"
to their nearest same-band neighbour, so lairs and lone hamlets are reachable.
Paths are cached Dijkstra per (source, class mask).

**Cultures** (SRD 5.2.1 only): human, dwarf, elf, halfling, gnome, orc, dragonborn, goliath,
tiefling, drow (species elf, lineage `drow`), and the monstrous goblinoid, kobold, gnoll and
bandit cultures. Each lists SRD stat blocks for guards, escorts, raiders and armies
(test-verified against `monsters.json`). Drow parties are NPC stat blocks (scout, bandit,
bandit-captain, spy, assassin, mage, priest, warrior-infantry/veteran) plus giant spiders.

**Settlement.** Cohorts (workers, dependants, soldiers), stockpiles of five goods, wealth,
morale, tier (hamlet/village/town/city by population with a 10% hysteresis), capacity from
biome x site size x culture. The garrison is derived: `soldiers` allocated over the
culture's guard recipe by largest remainder, so counts are always whole.
- Food: `cap * (1 - exp(-farm_workers * 0.38 * tools / cap))` per day, times season
  (0.75, 1.1, 1.55, 0.6) and the year's regional weather. Each person eats 0.1 a day.
  Food spoils 25% a year. Underground farming is unseasonal and poor (fungus).
- Labour: about two thirds farm (more when food is short); the rest cut timber and dig ore
  by where the land is rich, and make tools (+25% yield) and luxuries (morale). Full
  stockpiles send hands back to the fields.
- People: births up to 4.8%/yr scaled by how much more the land yields than the town eats
  in an ordinary year (or by a full granary, so imported or plundered food counts), deaths
  2.2%/yr, starvation 2.5% of the unfed per tick. Dependants come of age over 14 years.
- Coin: workers earn, soldiers cost upkeep, wealth decays 6%/yr. Broke towns lose soldiers.
- Prices: `base * clamp((target/stock)^0.8, 0.25, 6)`, target = population x yearly need x
  target years (food: three months).
- Below 12 people a settlement is abandoned: the site becomes ruins, survivors walk to the
  nearest friendly town.

**Trade.** Every econ tick, with some chance, a town with a surplus looks at the towns its
caravans can reach in 18 days that it isn't at war or bitter with, and ships the single most
profitable load (price gap x amount, minus wagon-days, discounted for isolationists, then for
recent danger on the path). Wagons and drivers are whole; the escort scales with the danger.
At market it sells what the buyer can afford, buys a return load, goes home. Each completed
trade warms relations (+2.5 each way); the first between two factions is chronicled.

**Raids.** Raiding drive = culture + temperament + hunger + poverty + war. A raid targets
either a route with recent traffic of a hostile faction (raiders wait in ambush halfway along
it for up to 12 days) or a reachable hostile settlement it expects to beat (odds >= 0.6).
Ambushes take cargo and coin, sometimes captives (drow, goblins), and sour relations;
patrols on the route join the defence, and patrols hunt raiders lying in wait. Towns send
patrols to routes where their caravans have been hit. Raided towns are less tempting for half
a year; raid parties have a 120-day cooldown.

**Lairs.** Monsters from `lairs.json` by band (surface, caves, deeps, portal). Hunger rises
over time; wild prey caps a modest lair at 3/4 hungry, so only crowded lairs grow hungrier.
Lairs hunt parties on routes near them (chance ~ hunger squared), and a lair past 3/4 hunger
sends a hunting pack against a town. Fed lairs breed up to a cap, starving ones dwindle.
Towns that lose people to a lair hold a grievance and send an expedition once strong enough;
a cleared lair yields its hoard. Ruins and empty lair sites are reoccupied over time. Apex
lairs (young dragons, purple worm, aboleth) demand tribute from the nearest town each year
when hungry, and burn it if it can't pay.

**War.** Relations drift monthly toward a base (same culture +25; monstrous vs not -20; drow
vs others -20; raider temperament -10). Raids and ambushes push them down. Below -60 a
faction may declare war (expansionists most). At war, a faction marches an army (70% of a
town's soldiers plus a levy of workers) at a reachable enemy town it expects to beat. A
siege halves the town's farming and lasts up to 40 days with periodic assaults. A won
assault means conquest (expansionists), sack (raiders), or tribute (others: 20% of wealth
yearly for 10 years). A town that fell is spared from armies for two years. War weariness
from time and losses brings peace. A faction with no towns falls.

**Outlaws.** Each year a hungry, miserable or tribute-paying surface town may lose 15-60
desperate people, who found a bandit camp (a new raider faction) at a free site or an empty
den within 16 days. This is the main source of raiders in otherwise peaceful worlds.

**Founding.** A large, well-fed, content town may send settlers (14% of its people, an
escort, food, timber, coin) to the nearest free settlement site or ruin in its bands.

**Food-shock tracking.** A famine (two econ ticks in a row with unmet food needs) opens a
one-year record per town: peak food price versus its ordinary price, food caravans arriving,
migrant columns leaving, raids launched. The sweep reports how often each response follows.

## Fights nobody watches

`BattleSimulator` was evaluated: about 1 ms per fight including building the combatants with
`SRDContent.make_monster` (a few hundred fights a year would be fine), but it swings only the
first attack action's first damage part (no Multiattack, no rider damage such as the
assassin's poison), uses the global `Dice` (needs `Dice.rng` swapped in), and allocates
objects per creature, which matters for armies of 100+. So `SimCombat` is a stack-level
resolver: per round each stack makes `count x attacks` swings with binomial-sized noise,
hit chance from attack bonus vs AC (nat 20 crit bonus approximated), damage applied to the
lowest-HP creatures first with overkill wasted (BattleSimulator's targeting), sides act in a
random order and the second swings with the average of its before/after numbers
(approximates interleaved initiative). A side routs at a chosen fraction of hit points lost;
the winner gets a half-strength pursuit volley. Ambushes add a free opening volley; walls add
AC. 27 us per fight.

Calibration (`run_history.gd -- calibrate=1 trials=150`, fight to the finish). "fast-c" is
SimCombat in compat mode (BattleSimulator's one-attack model); "fast" is the full model the sim
uses (Multiattack, all damage parts):

| matchup (A vs B) | BS A wins | fast | fast-c | BS A dead | fast-c | BS B dead | fast-c |
|---|---|---|---|---|---|---|---|
| 6 bandit vs 6 guard | 15% | 28% | 13% | 5.6 | 5.7 | 2.7 | 2.9 |
| 8 goblin-warrior vs 5 guard | 100% | 100% | 100% | 1.5 | 2.1 | 5.0 | 5.0 |
| 5 bandit + captain vs 4 commoner + 6 guard | 15% | 95% | 31% | 5.8 | 5.7 | 6.6 | 8.0 |
| 4 scout + 2 spy vs 6 warrior-infantry | 99% | 100% | 100% | 1.5 | 1.6 | 6.0 | 6.0 |
| 6 wolf vs 4 commoner + 3 guard | 96% | 100% | 99% | 2.0 | 2.1 | 7.0 | 7.0 |
| 2 ogre vs 8 guard | 39% | 57% | 67% | 1.6 | 1.2 | 5.6 | 6.8 |
| 1 owlbear vs 6 warrior-infantry | 34% | 93% | 41% | 0.7 | 0.6 | 4.0 | 4.5 |
| 5 gnoll + 3 hyena vs 8 warrior-infantry | 100% | 100% | 100% | 3.8 | 3.8 | 8.0 | 8.0 |
| 4 giant-spider vs 5 scout | 95% | 71% | 96% | 1.4 | 1.5 | 4.9 | 4.9 |
| 6 goblin + 6 hobgoblin vs 10 guard + captain | 79% | 50% | 91% | 7.6 | 7.2 | 10.5 | 10.9 |
| 1 troll vs 10 guard | 0% | 79% | 0% | 1.0 | 1.0 | 2.1 | 2.6 |
| 2 warrior-veteran vs 8 bandit | 93% | 99% | 99% | 0.5 | 0.5 | 7.9 | 8.0 |

Mean absolute win-rate difference: compat 6.4 points, full 26.1 points. The compat model
reproduces BattleSimulator well; the full model disagrees exactly where BattleSimulator leaves
out Multiattack (owlbear, troll, bandit captain), which is intended. Weakest spot: big ogres
vs many guards (compat says 67%, BS 39%): BS's guards gang up turn by turn, my averaging is
a bit kind to the big creature. Not modelled in either: breath weapons, spells, troll
regeneration, reach and ranged positioning.

## Tuning: the constants that matter

| Constant | Value | Why |
|---|---|---|
| `WORKER_FOOD` | 0.38 | per-capita yield on open land must beat eating (0.1) by ~1.6x or new towns starve |
| `FOOD_CAP` | 70/size/day | puts a size-2 plains town's equilibrium near 900-1000 people |
| `GROW_MARGIN` | 0.3 | births tied to the ordinary-year food ratio; towns settle ~10% below their limit instead of on it (the old stock-based births drove every town to the edge and every winter became a famine) |
| `SEASON_F` | .75/1.1/1.55/.6 | a sharper harvest cycle (0.4 winter) made chronic famines; this one leaves ~60 days of lean season |
| `STARVE` | 0.025 | at 0.05 a single blight killed 75% of a town in a year |
| blight | 7%/region/yr, yield 42-68% | 30% blights were extinctions, not shocks |
| `CROSS_DAYS` | 24 | at 40 days few towns were in caravan reach of each other |
| `RAID_P` | 0.02 | plus 120-day cooldown; at 0.05 goblin towns raided 3-5 times a year and wiped out neighbours |
| raid breaks | raiders 0.4, defenders 0.35 | defenders fighting to 70% losses meant every raid killed dozens |
| `LAIR_HUNT` | 0.03 | 0.35 made lairs the leading cause of death (caravan drivers) |
| lair sortie | hunger > 0.78 only | modest lairs at the wild-prey ceiling had been raiding towns every few months |
| war | rel < -60, 4%/month x temperament | starting hatreds were below the threshold; wars broke out in year 1 everywhere |
| `EQ_PER_CAP` | 6.5 | start populations at 35-80% of what the land feeds |

## Sweep statistics

`run_history.gd -- seeds=1..30 years=200 sites=24` (final code):

```
Sweep: 30 seeds x 200 years x 24 sites in 198.9 s
  worlds with negative stocks/pops: 0
  worlds trade_and_raids  29 / 30
  worlds grew             30 / 30
  worlds declined         30 / 30
  worlds fell_any         29 / 30
  worlds collapsed        0 / 30
  worlds exploded         0 / 30
  worlds shock_seen       30 / 30
  mean final/initial pop: 1.98
  food shocks: 1776; price rose >=50%: 77%; food imported: 45%; migration: 75%;
    raids launched: 35%; price rise + any response: 64%
  per world means: caravans 5981, ambushes 27, settlement raids 127, wars 5.7,
    conquests 0.9, sacks 8.1, foundings 6.1, settlements fallen 5.4, lairs cleared 17.3
  distinct chronicle signatures: 30 / 30
```

Notes: "grew" = some settlement reached 1.5x its first population (and >= 100); "declined" =
some settlement fell to 60% of its peak (peak >= 80); "fell" = an abandonment, conquest or
sack; "collapsed" = world population below 25% of its start, or no settlements; "exploded" =
peak above 6x the start. The worst world (seed 17, 1222 -> 771 people, 7 -> 2 towns, 11
sacks) is a deep-heavy world where drow and goblins grind each other down; an earlier
tuning had it below the collapse line. The single world without raids (seed 21) is all
peaceable surface peoples who never get miserable enough to breed outlaws; its history is
trade, famines, lairs and expeditions.

Smaller invariant sweep in `tests/test_sim_sweep.gd` (6 seeds x 100 years x 20 sites).

## Performance

Measured on this machine (`run_history.gd -- bench=1 sites=200 years=30`: 90 settlements at
the start, 134 at the end, 67 lairs, ~60 parties abroad):

- 2.08 ms per simulated day on average (0.087 ms per simulated hour, 10.4 ms per 5-day econ
  tick); the worst single day 20.6 ms (a day with econ, faction and yearly ticks together).
- Over the first simulated year with 90 settlements: 1.65 ms per day (asserted < 4 ms in
  `test_sim_world.gd`, target 2 ms).
- Breakdown per day: trade planning 0.73 ms, party movement and encounters 0.46,
  production/population 0.29, factions 0.16, raids 0.13, other decisions 0.14.
- 200 years x 24 sites: 8.5 s per world. The 30-seed sweep takes about 200 s.

So "a strategic tick for 100 settlements under 2 ms" holds if a tick means a simulated day
in a 90-110 settlement world, and is just over (2.08 ms) once the world grows to 130+.
Per econ tick (5 days) it is about 10 ms. The obvious next cut is trade planning
(evaluate from the buyer's side, or only re-plan when prices moved).

## Deviations from architecture.md

- `from_meta(meta, seed)` uses `meta.surface.size()` as world width; sites without routes
  get extra "trail" routes (flagged `trail: true` in `sim.routes`).
- Unwatched fights use `SimCombat`, not `BattleSimulator` (reasons and calibration above).
- Invented names come from a syllable generator in `data/sim/names.json`, as this track's
  brief asked, not from `data/setting/names.json` (which is still empty). Merge them later if
  the setting file becomes the single source.
- Extras not in the contract: `entities_near`, `party_position`, `audit`, `describe`,
  `stats`, `SimHealth`.
- Saves: `to_dict()` is JSON-safe and `from_dict(to_dict())` is exact. Godot's JSON drops the
  last bit of some floats even with `full_precision`, so for bit-exact save and resume use
  `var_to_bytes` (tested) or JSON accepting ~1e-15 relative drift (also tested).

## Materialization: what it will need (not built)

- Positions are already recoverable: settlements and lairs by site x; parties by
  (route id, fraction from route.a), and all counts are whole creatures and whole wagons.
- A mapping from strategic route to tile path (worldgen knows the real path; the sim only
  has its length), so a fraction becomes a tile position.
- A "frozen" flag per entity: while materialized, the sim must not move or resolve fights
  for it; on fold-back the view hands back survivors (slug counts), cargo and coin, and the
  sim writes them into the party or settlement. `SimParty.members/people/cargo/coin` and the
  settlement cohorts are the fields to write.
- Settlement interiors: who is a worker vs a dependant vs a soldier as actors, schedules,
  shop stock from `stock` and prices from `SimEconomy.price`.
- Events the player causes (a caravan escorted, a lair cleared by players) need entry points
  that log chronicle events and adjust relations/grievances, e.g. `sim.clear_lair(id, by)`.
- Seeded per-entity RNG for anything materialization rolls, so the sim's own RNG stream is
  not disturbed by what the player happens to look at (today one RNG drives everything).
- The addon's `make_npc(role, species, lineage)` (plan.md) to turn a drow "scout" into a drow
  scout actor; culture rows already carry species and lineage.

## Known weaknesses

- Seed 21 has no raids; outlaws need misery and a free site.
- Deep worlds with several raider cultures can grind each other down (seed 17 loses 5 of 7 towns).
- Populations rise on average (mean final/initial about 2x over 200 years); growth is
  bounded by land, but many worlds end near capacity rather than cycling.
- Food imports follow only ~40% of famines: caravans are push-based (sellers decide), and a
  blight usually hits a whole region at once.
- Army and raid targeting is greedy; no alliances, no coordinated multi-town campaigns, and
  the conquered keep their culture but have no revolt mechanic.
- Lair and dragon tribute is simple (pay 15% of coin or be burned); no territory beyond the
  routes near the lair.
- Wealth piles up in some trading towns (it buys nothing but food and escorts).
- Portals only spawn a small fiend lair; planar contact isn't modelled.
- Combat ignores spells, breath weapons, regeneration and terrain.

## Next steps

1. Run on real worldgen output (`from_meta`) across seeds and retune distances (route
   lengths are real tile walks now).
2. Buyer-side trade (a hungry town sends coin to buy food), which should raise the
   famine-relief rate and cut trade-planning cost.
3. Materialization hooks: freeze/unfreeze, fold-back writers, player-driven events.
4. Quest and rumour generation from `route_threat`, grievances, famines and wars.
5. Alliances and vassalage; revolts in conquered towns.
