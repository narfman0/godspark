# Track: sim-biomes (M5, the living world reads the land)

Directly on `main`, no worktree. Item 4 of [m5.md](../m5.md): biomes set food and goods, cultures
settle where they fit, routes across barriers cost what they should and are worth raiding, and
the sweep is re-tuned. The goal it serves: "Caravans carry scarce goods across barriers and get
raided for them." On medium seeds 1-3 that sentence is now true by the numbers below.

## What was built

### 1. Capacities

`data/sim/biomes.json` gives each biome a share of eight things; `goods.json` holds what a full
share is worth. Five goods are new, each with a job, because a good nobody needs is not traded.

| Biome | food | water | timber | game | ore | stone | salt | reagents |
|---|---|---|---|---|---|---|---|---|
| meadow | 1.0 | 1.0 | 0.4 | 0.2 | 0.1 | 0.15 | 0 | 0.1 |
| forest | 0.7 | 1.0 | 1.2 | 1.0 | 0.1 | 0.2 | 0 | 0.3 |
| swamp | 0.55 | 1.0 | 0.6 | 0.4 | 0 | 0 | 0.1 | 1.2 |
| mountain | 0.45 | 0.7 | 0.3 | 0.3 | 1.4 | 1.3 | 0.1 | 0.15 |
| desert | 0.35 | 0.12 | 0.05 | 0.1 | 0.4 | 0.5 | 1.4 | 0.1 |

| New good | Base | What it does |
|---|---|---|
| salt | 5 | With it food spoils at half rate, without it at 1.5 times |
| stone | 3 | Under a quarter of target, a town's walls count a step lower |
| reagents | 12 | Natural deaths run 0.85 to 1.2 times the rate |
| game | 2.5 | Eaten when the granary is empty, a unit for three of food |
| water | 0.2 | Comes up by itself to the biome's cap; a dry field yields 55% |

- Production, stock caps and prices all read the row. `price` is base x land x scarcity, the land
  running 1.3 where it gives none to 0.7 at a full share. `stock_cap` lets a town stockpile what
  its land gives, so a desert town holds salt to sell.
- Workers split over every raw good by capacity. The labour rates are higher than my first numbers
  (ore 0.05 to 0.15): at those, ore and salt sat at the price ceiling in most towns.
- Meadow's food stays 1.0, so one-biome worlds feed as before.

### 2. Cultures

Every surface culture now names all five generated biomes, so a misfit is a choice and not the
0.4 default. `underdark` has weights: drow 5, dwarf 2, goblinoid 2, kobold 2. Those last two gain
the `deeps` band, since no generated settlement is band `caves`, and deep towns were only ever
dwarf and drow. A run of kin continues at 0.25 x fit (at most 50%), so elves stop following their neighbours
into the desert. Founders walk further for land that suits them. SRD species only; no setting
names.

Who the first settlers were, medium seeds 1-5:

| Biome | Settled by |
|---|---|
| meadow | human 12, halfling 3, elf 2, tiefling 1, gnoll 1 |
| forest | elf 7, goblinoid 6, bandit 3, human 3, gnome 2, orc 1 |
| swamp | tiefling 5, bandit 3, gnoll 2, goblinoid 2, orc 2, gnome 2 |
| mountain | orc 1, dwarf 1, bandit 1, goliath 1 |
| desert | gnoll 10, dragonborn 5, tiefling 4 |
| underdark | drow 12, kobold 3, dwarf 3, goblinoid 2 |

### 3. Routes and raids

- **Every route knows what it crosses.** `route.crossings` holds kinds. Roads keep worldgen's length,
  which already holds the cost. A trail adds it, and picks the nearest site on foot, so a lair just
  over a range trails to its own side. Underground routes cross nothing.
- **Bulk stays home, dear goods travel.** `WAGON_DAY_COST` went from 0.6 to 5. It is a planning
  cost, not paid in coin. At 0.6 a pass cost a wagon 1.4 coin and changed nothing; at 5, cheap loads
  stop going far.
- **Raiders want the richest train likely to come by.** A raid takes one train and goes home, so
  the weight is coin a trip x the chance one passes in 12 days x distance. `route_value` holds
  the coin, by faction, decaying as traffic does.
- **A road over a barrier pinches its wagons.** `PINCH` adds 1.0 to a route's worth to a raid for a
  pass, 0.35 for a ford or bridge. At an earlier tuning, value alone gave the pass only 14% more
  ambushes than a flat road, because the flat roads beside it carry the same long-haul trains.
- Caravans still run: 13 186 a world over 100 years against 12 407 before.

### 4. The report tool

`tools/trade_report.gd -- gen=medium seed=N [days=3600] [cache=/dir]` prints every route, the flows
of goods between biomes, and pass, river and flat roads side by side. It reads a ledger the sim
fills only when asked (`ledger_on`).

`tools/run_history.gd -- seeds=1..10 years=100 world=dev` sweeps generated worlds, with a table per
biome and per road kind. `cache=/dir` keeps what the sim reads of each world, for tuning.

## Numbers

All runs 100 years. "Before" is 75cf63e with the sweep tool added. Dev and synthetic: 12 seeds.
Medium: 10 seeds. Means per world.

### Whole worlds

| | synthetic before | after | dev before | after | medium before | after |
|---|---|---|---|---|---|---|
| people, start | 2198 | 2131 | 2403 | 2730 | 8901 | 10360 |
| start range | 1200-3701 | 755-3713 | 1501-3993 | 1685-4015 | 6647-11661 | 8004-12101 |
| people, year 100 | 3466 | 4486 | 4696 | 5898 | 16601 | 21977 |
| final / initial | 1.56 | 2.16 | 1.95 | 2.19 | 1.87 | 2.12 |
| settlements fallen | 3.8 | 3.2 | 0.6 | 0.1 | 2.8 | 2.9 |
| famines | 25.2 | 21.7 | 17.2 | 15.8 | 64.6 | 66.4 |
| caravans | 2135 | 2399 | 1903 | 1543 | 12407 | 13186 |
| coin traded | 318k | 533k | 522k | 727k | 1.81M | 4.03M |
| ambushes | 10 | 21 | 2 | 7 | 65 | 198 |
| town raids | 100 | 102 | 15 | 32 | 158 | 150 |
| wars | 5.8 | 5.2 | 1.1 | 0.8 | 10.5 | 13.3 |
| conquests | 0.9 | 1.2 | 0.2 | 0.2 | 4.0 | 8.6 |
| sacks | 8.4 | 7.9 | 1.4 | 1.5 | 18.0 | 19.6 |
| worlds collapsed, exploded | 0, 0 | 0, 0 | 0, 0 | 0, 0 | 0, 0 | 0, 0 |
| worlds with audit problems | 0 | 0 | 0 | 0 | 0 | 0 |

Starting people did not come back: dev is up 14% on a 12-seed base, not the third the biomes track
lost. I left `_initial_pop` alone, because it sets tiers and so what gets built in every town. Worlds
start about half full and fill within a century.

### Per biome, medium, 10 seeds

Places and people are per world at year 100. Hungry, short and rich are shares of
settlement-seasons. Short is under a third of a season's food, or hungry; it was not measured before.
Rich is a full granary and 3 coin a head, the smith's line for a rich town. Town is 600 people.

| Biome | places | people | a place | largest | towns | hungry before | after | short | rich before | after |
|---|---|---|---|---|---|---|---|---|---|---|
| meadow | 5.6 | 8305 | 1126 | 2262 | 4.9 | 0.7% | 0.7% | 5.5% | 59% | 48% |
| forest | 5.5 | 4591 | 648 | 1702 | 3.4 | 1.1% | 0.7% | 10.6% | 33% | 15% |
| swamp | 4.6 | 2406 | 432 | 1493 | 2.0 | 1.1% | 1.1% | 8.0% | 42% | 36% |
| mountain | 1.6 | 1081 | 368 | 1507 | 0.9 | 0.3% | 0.7% | 4.0% | 77% | 77% |
| desert | 4.7 | 2408 | 392 | 845 | 2.6 | 0.7% | 0.8% | 4.2% | 41% | 56% |
| underdark | 4.9 | 3186 | 572 | 1100 | 3.1 | 0.3% | 0.8% | 4.0% | 69% | 28% |

Towns of 600 or more, before: meadow 4.1, forest 2.6, swamp 1.3, mountain 0.1, desert 0.2, underdark
3.5. Deserts and mountains now hold towns, because a town with 3 coin a head buys food enough to
outgrow its land. No biome is always starving or always rich. The mountain is the richest at 77%:
it has few people and sells what everyone needs. The forest is the poorest, at the cold end far
from the salt.

Dev worlds (12 seeds) agree, but have **no mountain towns at all**, before or after: the range takes
the mountain's flats at that width. Meadow 1004 a place, forest 872, underdark 711, swamp 526, desert
357.

### Roads, medium, 10 seeds, per road over 100 years

| Road | a world | coin carried | trips | coin a trip | ambushes | caravans lost |
|---|---|---|---|---|---|---|
| over a pass | 1.0 | 1 915 000 | 4925 | 389 | 26.1 | 23.9 |
| ford or bridge | 3.0 | 1 279 000 | 3588 | 356 | 11.3 | 10.8 |
| flat | 16.2 | 1 466 000 | 4178 | 351 | 8.1 | 7.7 |

So a pass carries 31% more coin than a flat road and is ambushed 3.2 times as often. Rivers are
ambushed more than flat roads but carry less coin: they lie inside one biome, so what crosses them
is whatever passes through. Seeds 6-10 taken alone give a pass 356 coin a trip against 352, so
the higher coin a trip is not solid on every set of seeds. The higher total and the ambushes are.

There is no before for this table. The ledger did not exist.

### Trade report, medium seeds 1-3, 10 years

The closing line of each:

```
seed 1: 458 caravans in 3600 days; 74% of the coin carried crossed a barrier, 80% moved between unlike biomes; 25 ambushes, 25 caravans lost.
seed 2: 1081 caravans in 3600 days; 61% of the coin carried crossed a barrier, 77% moved between unlike biomes; 22 ambushes, 20 caravans lost.
seed 3: 309 caravans in 3600 days; 61% of the coin carried crossed a barrier, 79% moved between unlike biomes; 34 ambushes, 32 caravans lost.
```

Pass, river and flat, coin a road and ambushes a road:

| Seed | pass | river | flat |
|---|---|---|---|
| 1 | 93 144, 2.0 | 49 415, 2.3 | 46 298, 0.9 |
| 2 | 132 062, 2.0 | 106 748, 1.3 | 106 808, 0.9 |
| 3 | 93 258, 8.0 | 15 124, 0.3 | 39 462, 1.4 |

Seed 3, the road over the pass and the top of its flows:

```
  id from   to     length hours crossings     trips     value ambus taken     lost beast  goods / raiders
  13 meadow mounta   2405   169 pass            209     93258     8     8     1911     0  salt 4295, timber 2752, ore 1014, food 2728  bandit 1 gnoll 1 goblinoid 5 human 1

  good      from       to             units      value  a unit  crossed
  salt      desert     meadow          2545      38744   15.22  pass
  salt      mountain   meadow           949      16915   17.82  pass
  salt      desert     mountain        1374      12063    8.78  -
```

Seed 1, what goes the other way:

```
  salt      desert     meadow          4487      24781    5.52  pass
  timber    meadow     desert          4970      22582    4.54  pass
```

Salt reaches meadow prices of about three times base and timber reaches the desert at more than
twice base. Over 10 years a pass sees 2 to 8 ambushes, so some years pass with none.

## Tests

`tests/test_sim_biomes.gd`, about 190 checks, about 30 s: each biome's table and what a lone town
holds on it over 8 years; prices and stock caps by land; each new good's job; culture picks over
many draws; a trail with and without a pass (5% of width, in hours and in wagon hours), a trail that
turns to its own side, a deep trail that crosses nothing, crossings through a save; a real dev
world's roads keep their length, and every place is built for the culture the host's sim seats there;
raid weights for a richer route, a few rich trains against many carts, a pinch, friends' cargo, and
400 launched raids; an old save without the new goods; 6 dev worlds over 60 years against the
health bars.

No existing test changed and no test seed moved.

## Changes not asked for

- `core/world/worldgen/stage_places.gd` passes the barriers to its sim. Without it, a trail that
  turned to its own side changed the RNG draw of route names, and a town could be built for a culture
  other than the one living there. One line, and tested.
- `data/items/base.json`: five `trade:` rows. The recover quest and Life's dropped cargo make these
  items, and a missing one would have failed or turned to coin.
- `tools/soak.gd`: `wall=`, see below.
- Raiders that go out hungry now fall on who they set out for. The route choice accepted anyone
  under 40 relations when hungry, but the ambush only accepted enemies. On one medium seed about
  three quarters of route raids ended with no ambush; this fix took ambushes from 121 a world to
  174.
- `price_ref` averages over 250 days, not 100. Towns importing food sit at high prices, and the
  faster average had caught up with a shortage before it became a famine, so "price rose by half"
  fell from 82% of shocks to 18%. It is back at 66%.
- A town with 3 coin a head buys food up to 1.9 stock targets. Without this a rich mountain town
  stays the size of its land, since a full granary alone only just pays for deaths.
- Raids on a town also take reagents and salt.
- `ROUTE_VALUE` is 15, tuned so that routes and towns draw raids about equally.

## Measured otherwise

- **Sim cost:** 2.5 ms a simulated day at 84 settlements (the test's limit is 4). A medium world's
  100 years takes about 17 s, up from about 10 s: twice the goods. I did not profile it.
- **Suite:** 8347 checks, ALL PASS, about 3 min 50 s.
- **Smokes, one at a time, each NET SMOKE PASS:** plain 14 s, `LIFE` 20 s, `DEALS` 21 s,
  `WORLD_LIFE` 179 s, `ALL` 65 s.
- **`tests/test_m4_e2e.gd` twice, unseeded:** 144 checks, ALL PASS both times.
- **Passability, not asked for:** cultures and tiers move what gets built. Medium seeds 1-4: 113/113,
  116/116, 114/114, 113/113 on foot, the same as the barriers track, and every crossing walked both
  ways. Seed 5 ran out of its 300 s. The sweep's five default dev seeds: 168/168.

### Soak

`days=60` cannot run under the 300 s limit: real ticks reach about 2 game days in 210 s, so 60 days
is about 1.7 hours. I added `wall=`, which stops the run and reports on the ticks it did, and
ran two within the limit.

| | medium seed 3, aged 60 days | medium seed 2, aged 3600 days |
|---|---|---|
| game days of real ticks | 2.08 | 1.50 |
| tick avg, p99, max, ms (budget 33.3) | 2.82, 6.40, 48.65 | 2.75, 6.27, 50.71 |
| static memory, MB | 219.7 to 235.0 | 220.5 to 236.1 |
| script errors, audit, books | 0, clean, matched | 0, clean, matched |

The worst ticks ran over the 33.3 ms budget: 51 ms with system 5 at 46 ms, and 49 ms on a sim step
with no system to blame. I did not trace them or compare them with before this track. Memory rose
about 15 MB in each short run, too short to say anything about the 5 MB a day in `docs/todo.md`.

## Open and unverified

- **The 60-day soak was not run**, as above.
- **Not played by a human.** Nothing here is visible yet except through chronicle lines, shops and
  who lives where.
- **Shops don't sell the new goods.** The items exist, and players can sell them; `data/deals/prices.json`
  has no shelf rows for them. Left out as not asked for.
- **`item_icons.gd`** has no icon of its own for the new trade goods. Not looked at.
- **Water caravans are rare.** Desert wells held for the towns seen, so water is mostly a soft cap,
  and no water flow reaches the top 24 of a report. `DRY_FIELD` and desert water are the handles.
- **The forest stays poor,** short of ore and salt at 7 times base with no coin to buy them.
  That may be right for the cold end, or a poverty trap. It holds 3.4 towns and doesn't fall.
- **Deep roads carry almost nothing.** Underdark towns share one biome, so nothing is cheap at one and
  dear at another, and the one link route takes what trade there is.
- **Mountains on dev worlds have no towns**, so the sweep test can't check them. The test's lone
  towns do.
- **Dwarves don't always hold the mountains.** A medium world has 1 to 3 mountain sites, so small
  samples vary: 1 of 4 in the table above. The picks test shows the weights hold over many draws.
- `WAGON_DAY_COST` is not charged. A caravan plans with it and pays nothing.
- Medium conquests doubled (4.0 to 8.6) and wars rose by a quarter. Ambushes hurt relations, and I
  did not separate that from richer targets.
- Ambushes on medium tripled while town raids held. About 1.4% of caravans sent are lost to them.

## Limits

None broken. One headless Godot at a time, with the memory gate before each and each under its
`timeout`. The medium passability sweep hit its 300 s on seed 5, as said above. I waited for the
verification already running on main to finish before editing there. ComfyUI not touched, no art
committed, nothing pushed.

The commits use the Opus attribution the session gave me rather than the brief's Fable line, since
Opus wrote them.

## Seams for later tracks

- **Life and Deals:** `data/deals/prices.json` shelves for salt and the rest; `item_icons.gd`.
- **Map:** `route.crossings` on the sim's routes, and `route_value` for showing which roads are rich.
- **Rumours:** `sim.route_value` is what a tavern would know. The ledger is for tools only.
- **Spawning:** `route_threat` already says where it has been dangerous lately.
- **Tundra, coast, hills, jungle:** rows exist with every share, untested on generated land.
- **Sweeps:** `SimHealth.observe` takes any sim, `tools/run_history.gd` a `cache=` directory.
