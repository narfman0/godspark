# Track: peoples below (M6, track 2)

Directly on `main`, from e13b6bd. Item 3 of [m6.md](../m6.md): drow cities, duergar holds, deep gnome
warrens, goblin and kobold warrens placed by the sim's culture weights on underground biomes, built
from kits, lamp-lit, peopled like surface towns, trading along deep roads and up to the surface, and
meeting players by their own rules. Track 1 (deep biomes, `ws/deep`) had not landed: every deep site
still carries `underdark`, and everything here reads the site's own biome, so it takes the regions
when they come.

## What was built

### 1. The deep peoples as cultures (7d6e1bd)

SRD 5.2.1 has no drow, duergar or deep gnome stat block, and no duergar or deep gnome lineage (the
addon's `NPC_LINEAGES` has none either). So: drow are the Elf with the Drow lineage, as before;
**duergar** are dwarves and **deep gnomes** gnomes, each with the tag `deep`; all three are SRD NPC
blocks through `make_npc`. Goblins and kobolds are as they were (their own blocks).

| People | Best land (weight x culture weight) | Makes (land share x) | Wants (stock target x) | Temperament |
|---|---|---|---|---|
| drow | underdark 5, fungal 4, crystal 2, caves 2, deep lake 2 (x3) | reagents 1.5, crystal 1.3, ore 0.6, stone 0.7 | food 1.3, timber 1.8, luxuries 1.3, ore 1.2 | raider 4, expansionist 2, trader 1 |
| duergar | crystal 5, magma 5, underdark 2.5, caves 2 (x2.5) | ore 1.35, stone 1.4, reagents 0.35, timber 0.5 | food 1.3, reagents 1.4, timber 1.4 | isolationist 3, trader 2, expansionist 2, raider 1 |
| deep gnome | crystal 5, caves 5, underdark 1.5 (x1.8) | crystal 1.6, ore 1.15, reagents 0.6 | food 1.2, luxuries 1.2, salt 1.3, reagents 1.2 | isolationist 4, trader 3 |
| kobold | caves 4, magma 4 (was 2), crystal 2, underdark 2 (x1.5) | ore 1.25, reagents 0.5, timber 0.6 | food 1.2, tools 1.4 | as before |
| goblin | caves 4 (x2.5) | as before | as before | as before |

Dwarves of the surface no longer settle the deeps (their `bands` lose `deeps`); the duergar have them.

- **makes** scales the land's share of a good for that people, so the yield, the local price and
  the stockpile all follow; under 1 means they don't make it and buy it. **wants** scales the stock
  target, so they keep more and pay more. Both are optional in `cultures.json`; a people that names
  nothing is unchanged.
- **Crystal** is a new raw good (base 8, need 0.03, use 0.01, mostly of the crystal caverns, 1.2 there,
  0.4 underdark, 0.3 magma and caves, 0.15 mountain). Its job: fine goods are cut from it before ore,
  and lamps wear it out. My first numbers (need 0.1, use 0.03) priced it at the ceiling in every
  surface town and cost a dev world a tenth of its people over 60 years; at these it costs nothing
  measurable. No gems good: the table had none and one luxury mineral was enough.
- **roles** in a culture name the SRD block for townsfolk, keeper, merchant, smith, priest, mage,
  guard, scout and raider; **first_roles** who a town shows first by tier (a drow city shows its
  priests and mages). `Life.role_slug` and `Life.first_roles` read them before
  `data/life/people.json`, which gained `mage`, `scout`, `guard`, `raider`.

| Role | drow | duergar | deep gnome | kobold | goblin |
|---|---|---|---|---|---|
| townsfolk, keeper | commoner | commoner | commoner | kobold-warrior | goblin-minion |
| merchant | noble | commoner | noble | kobold-warrior | goblin-minion |
| smith | commoner | warrior-infantry | commoner | kobold-warrior | goblin-minion |
| priest | priest | priest | priest-acolyte | kobold-warrior | goblin-minion |
| mage | mage | mage | mage | kobold-warrior | goblin-boss |
| guard | warrior-infantry | warrior-infantry | guard | kobold-warrior | goblin-warrior |
| scout | scout | scout | scout | kobold-warrior | goblin-warrior |
| raider | spy | warrior-veteran | scout | kobold-warrior | goblin-warrior |

Traits, as `make_npc` gives them and the tests check for every role: drow Darkvision 120 ft (Drow
lineage), duergar Darkvision 120 ft and Dwarven Resilience (poison), deep gnomes Darkvision 60 ft and
Small, kobolds and goblins their blocks' Darkvision 60 ft. **Sunlight Sensitivity** is on the SRD's
Kobold Warrior block only: the SRD 5.2.1 Drow lineage gives Darkvision 120 and Dancing Lights, not
Sunlight Sensitivity (the addon's old `species_data.gd` "Dark Elf" is 5.1 and unused here). No
combat rule models Sunlight Sensitivity yet; see open.

Also: the drow's estrangement from every other people is data (`estranged` 20, the same numbers as
the old hard-coded rule), and so is how far relations may fall before a people's caravans stop
going (`trade_floor`, default -20; drow -50). Name syllables for duergar and deep gnomes
(`data/sim/names.json`), and `data/setting/names.json` gains `deep`: each people's word for its
settlements and the forms a map or a guard uses ("the city of Zaerrith", "Kolzul Deephold", "the
warren of Glimnook"), picked by a hash of the name (`SimNames.title`, `kind_word`). Smith racks,
talk lines, Bonds (knacks), map colours and look rows (`people:dwarf:deep:*`, `people:gnome:deep:*`,
grey tints) for the two new peoples. `Life.people_key` draws a deep people without a lineage as
`species:deep`.

### 2. Deep settlements that are towns (cb7794d)

The sim already placed deep settlements by culture weight on the site's biome, and Life already
peopled them. What was missing was their look and light.

- `PlaceStyles.style_for(culture, band)`: below the surface goblins and kobolds build warrens
  (`styles.json` `deep`); on the surface goblins still camp in tents. Worldgen's places
  (`PlaceBuilder.plan` reads the site's band) and a founding (`PlaceKeeper.apply`) both use it.
- Styles: **duergar** granite and slate by torches, **deep_gnome** mossy stone and planks by lamps,
  **goblin_warren** logs and canvas by torches, **kobold_warren** granite by torches; drow as before
  (dark stone, violet fae lamps). Every deep style has an emissive lamp tile, and `street_lamps`: a
  lamp hangs over the street in the gap left of each building, gone with a ruin. Without it a quarter
  of a duergar hold's people stood in the dark on dev seed 4. No roof is of a tile the cave dressing
  grows on (a giant mushroom grew on the first duergar roof I pictured).
- Kits from the Synty dungeon and cave pieces, twelve appended to `data/dressing.json`: stone lantern,
  large gem, gem spike, giant mushroom, dungeon brazier, bonfire, stone throne, chest, candle stand,
  dungeon bed, goblin tent, skull pile. Kits `duergar`, `deep_gnome`, `goblin`, `kobold`, and the drow
  kit takes the giant mushroom, candle stand and stone throne. Light is always the lamp tile, never
  a model. `tests/data/asset_paths.txt` refreshed (201 of 201 on the server).

### 3. Deep roads as trade (2f7e182)

On one rock every deep town made the same things, so a deep road carried almost nothing (the
sim-biomes track said so). The makes under 1 above fix that today, before the regions: what one
people makes the next buys. Duergar, deep gnomes and kobolds trade down to relations of -45, -40 and
-45, so a drow city and a duergar hold trade unless at war. Surface peoples still travel by road
only: goods go up on deep caravans and come down as their return loads.

- **Ways up.** Today's worlds have one: worldgen's ascent route (a deep settlement to the surface
  settlement nearest the mouth), a `link` in the sim. `meta.barriers` lists passes, under-routes and
  river crossings, all surface to surface; no cave mouth is listed in meta. So I added the seam the
  descent track can fill: `meta.ways: [{kind, top: [x, y], bottom: [x, y]}]`. Each joins the deep
  settlement nearest its bottom to the surface settlement nearest its top as a link (`route.way`
  names its kind), unless a route already does; a save keeps it. Caravans use it when it pays.
- `SimHealth.route_shares` counts `deep` and `link` routes; `SimHealth.observe` reports the deep
  settlements (start, end, fewest, how many of the first stand, by whom); `tools/run_history.gd`
  prints both; `tools/trade_report.gd` marks each route `road`, `deep` or `link` and compares deep
  roads and links with the surface roads.

### 4. Hostility and the toll (f96f085)

All in `cultures.json` `stance`, on top of standing (`data/life/standing.json` as before).

- **Drow abroad:** `abroad: hostile` and `spare_at: 10`. A drow who is not one of a settlement's
  people and stands on the surface (`abroad_on`, default surface) attacks a player whose standing
  with its city is under 10: raiders, escorts, anyone of a party. Raiders still spare only at 60.
  Killing a drow who would have fallen on you there costs no standing; killing one at home still does.
- **Drow at home:** neutral, for a **toll**: 5, 10, 25 or 50 coin by tier, paid to a guard in the real
  dialogue ("Pay the toll (10 coin)"), into the town's treasury; or a favour of 8 standing; good for a
  game day, saved with the player; nothing for a friend of the city (standing 30). Arriving, the player
  gets a second note: "The gate guards want a toll of N coin to go further." Ten tiles inside the
  outermost building unpaid, the player has 20 seconds to find a guard; then the town's people turn
  on them, and walking out makes them neutral again.
- **Standing from trade:** buying from or selling to a faction's shops earns 0.02 standing a coin, at
  most 20 from trade alone. So 500 coin of trade, or quests, turn the surface drow neutral.
- **Duergar and deep gnomes are wary:** never hostile by their own rule, friendly only at 50 and 45.
  Kobolds, goblins and the surface peoples are as before.

### 5. Pictures (1996302)

`game/ui/world_tour.gd` `tour=deep`: the real client and UI, offline host with cheats.

```
tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=4 \
    world=DIR world_tour=DIR timeout=280 tour=deep
```

In `/tmp/claude-1000/-home-narfman0-workspace/7cf54a79-3f3e-43af-87e7-ba72c23eb7f8/scratchpad/shots/`,
looked at:

- `30_drow_gate.png`: the banner "Kyryszhar, a drow village of 407 souls, House Kyrydril" over a
  street of violet dark-stone houses, fae lamps on the walls and hanging over the street, guards with
  work marks, a giant mushroom at the right edge. Black above and below the cavern.
- `31_toll_asked.png`: the dialogue with "Qelthaun, guard of Kyryszhar": "10 coin at the gate, or you
  go no further." Options: Any news? / Pay the toll (10 coin). / Any work? / Farewell.
- `32_toll_paid.png`: "The city remembers who pays.", the toll option gone, -10 beside the purse
  (400 to 390).
- `33_drow_street.png`, `34_drow_street_wide.png`: the street by lamplight, two-storey houses with
  ladders and beds upstairs, townsfolk at a table, guards with spears, a mage in robes, the hanging
  street lamps between buildings. The drow are tinted Synty humans; they read as people in a violet
  town, not obviously as drow.
- `35_duergar.png`: Zhurgrond, granite walls warm under torches, beds and tables, guards and
  townsfolk on the street; no mushroom on the roofs.
- `36_deep_gnome_warren.png`: the same site refounded by deep gnomes (a cheat: no generated world
  has a deep gnome warren with a place in the worlds I looked at), mossy stone with green edges,
  lamps, a red gem spike in the square. Its people are not visibly smaller than the duergar were: I
  did not check whether they had re-materialized before the shot.
- `37_map_deep.png`: the map's Deeps band with Kyryszhar and Zhurgrond named, the deep road between
  them and the link climbing to the surface.
- `look_duergar.png` (look_shot): the same hold drawn by look_shot, lit.

The first tour run drew the duergar hold black for at least 8 seconds after a 900-tile teleport,
while the core light engine had it at 50 to 70 and look_shot drew it lit. Coming in from 300 tiles
off, as a walker would, it is lit; the tour now does that. See open.

## The contract as built

```gdscript
# data/sim/cultures.json, optional per culture
tags: ["deep"]; makes: {good: f}; wants: {good: f}; roles: {role: slug}; first_roles: {tier: [roles]}
estranged: n; trade_floor: n
stance: {abroad: "hostile", abroad_on: ["surface"], spare_at: n, friendly_at: n,
         toll: {coin: {tier: n}, standing: n, free_at: n, days: n, margin: n, grace_s: s}}

SimData.make_f(culture, good) / want_f(culture, good) / is_deep(culture) / role_slug(culture, role)
SimNames.title(culture, name, band := "deeps") / kind_word(culture) / deep_style(culture)
Life.first_roles(culture, tier) / Life.role_slug(culture, role)
PlaceStyles.style_for(culture, band)
WorldSim._setup(..., barriers, ways)        # meta.ways -> link routes, route["way"]
SimHealth.route_shares(sim)["deep" | "link"]; SimHealth.observe(...)["deep"]
LifeSystem.culture_stance(faction) / abroad(x, cs) / band_at(y)
LifeSystem.toll_due(player, sid) -> int / pay_toll(player_id, sid) / trespassing(p, x)
LifeSystem.inside_gate(sid, pos) / town_span(sid) / trade_standing(player_id, faction, coin)
LifeSystem.save_player: + tolls {sid: sim hour}, traded {faction: coin}
DealsSystem.pay_toll(e, favour := false)    # options "toll", "toll_favour" at a guard
data/deals/lines.json: offers.toll, offers.toll_favour, toll_ask, toll_paid
data/life/standing.json: trade_per_coin 0.02, trade_cap 20
data/places/styles.json: deep {culture: style}; style street_lamps
```

## Numbers

### The sweep: medium, 10 seeds, 100 years

`tools/run_history.gd -- seeds=1..10 years=100 world=medium cache=DIR`. Before is e13b6bd in a
detached worktree with this track's `sim_health.gd` and `run_history.gd` copied in (they only read),
on the same cached worlds; its whole-world numbers match the sim-biomes track's medium column.

| | before | after |
|---|---|---|
| people, start / year 100 | 10360 / 21977 | 10352 / 22695 |
| final / initial | 2.12 | 2.21 |
| worlds collapsed, exploded, with audit problems | 0, 0, 0 | 0, 0, 0 |
| caravans a world | 13185 | 14913 |
| coin traded a world | 4.03M | 4.49M |
| ambushes, town raids | 198, 149 | 158, 137 |
| wars, conquests, sacks | 13.3, 8.6, 19.6 | 9.4, 6.0, 11.2 |
| settlements fallen, founded | 2.9, 9.1 | 2.7, 8.8 |
| famines | 66.4 | 63.4 |
| **deep settlements** a world, start / end / fewest | 4.0 / 4.9 / 4.0 | 4.0 / 4.8 / 3.6 |
| of the first 40, standing at year 100 | 40 | 38 |
| deep settlements at year 100, by people | drow 25, goblin 11, kobold 7, dwarf 6 | drow 19, duergar 17, goblin 6, kobold 3, deep gnome 3 |
| **deep roads** (5 a world): coin, trips a road | 60769, 139 | 121517, 316 |
| **links** (1 a world): coin, trips, ambushes | 176291, 526, 2.3 | 511634, 1515, 7.3 |
| pass roads: coin, trips, ambushes | 1.91M, 4925, 26.1 | 2.12M, 4870, 25.6 |

Deep settlements live the century: 38 of 40 stand at year 100 and the deeps end with more towns than
they started with. Deep roads carry twice what they did and the links up nearly three times, with
ambushes on the links. Wars fell by a quarter and sacks by 40%; I did not separate the causes
(duergar for dwarves underground, trade warming relations across the deep roads, drow trading
further). Per biome the underdark's people are about the same (3145 against 3186 at year 100), the
mountain's towns grew (1.2 against 0.9 a world).

Dev worlds, seeds 1-6, 60 years (the suite's own sweep test): ending people 4963 against 5137 before,
meadow 840 a place against forest 779; deep roads went from 0 trips on dev seed 4's drow-duergar
road in ten years to 19.

### Trade report, medium seed 1, 10 years

```
    24 link underd meadow   1595   112 -                55     18341     0     0        0     0  ore 940, timber 1021, reagents 127, crystal 184
    21 deep underd underd   1138    80 -                 5      1014     0     0        0     3  tools 54, ore 40, food 120
    22 deep underd underd   1497   105 -                32     12671     0     0        0     7  ore 447, timber 831, crystal 184, reagents 85
  deep    5 roads: each      2737 coin in     7 trips ( 369 coin a trip),   0.0 ambushes,   0.0 lost,  2.0 lair attacks
  link    1 roads: each     18341 coin in    55 trips ( 333 coin a trip),   0.0 ambushes,   0.0 lost,  0.0 lair attacks
```

Ore, reagents and crystal go up the link; timber comes down on the return loads; deep ore reaches a
swamp town over a ford (473 units at 14 coin).

## Tests

`tests/test_peoples_below.gd`, 793 checks, about 10 s:

- cultures: every biome weight canonical, every makes and wants a real good, temperaments the sim
  knows; each deep people settles the deeps on underground land; the brief's homes and goods; picks
  over 600 draws on six underground biomes; a generated world's deep towns on underground biomes.
- roles: every role of every deep people a real SRD block that `make_npc` builds, with Darkvision,
  Dwarven Resilience and size checked; Sunlight Sensitivity where the SRD gives it.
- names and titles, no Forgotten Realms names (menzo, gracklstugh, blingden, svirf and others).
- makes, wants and crystal on a town, and crystal cut before ore, unit for unit.
- each people's town built from its kit in a black cave: its style, an emissive lamp, at least four
  kit pieces, every column of the built town lit, no sun; on dev seed 4 a drow and a duergar town
  materialize with keeper, merchant and guards on the street, in lamplight, drawn as their people,
  with a store selling what they make, a smith, work and their own lines.
- a drow caravan's load leaves its stores and every unit and coin at market and home is in one store
  or the other; ten years of a drow city, a duergar hold and a human town moving goods up, down and
  between the deep towns, the audit clean; `meta.ways` becomes a link and survives a save.
- the toll by tier, neutral at the gate, the grace then hostility past it, paying in coin and by
  favour, a paid toll through a save, a purchase raising standing, a drow on the surface hostile to a
  stranger, friendly to a friend, neutral to a trader at 10, no standing lost for fighting back, the
  duergar wary.

No existing test changed. No test seed moved.

## Changes not asked for

- `SimEconomy._tick_settlement` reads raw-good caps with `.get(g, 0.0)`: `test_sim_biomes` builds
  towns with an eight-key cap table, and a ninth raw good failed it with a script error.
- Dwarves leave the deeps to the duergar (their `bands` lose `deeps`).
- The drow kit's statue is a giant mushroom, its shrine post a candle stand, its throne the stone
  throne.
- Arrival notes say "deep gnome", not "deep_gnome".
- `game/ui/emblems.gd`: map colours for duergar and deep gnomes; `data/rules/knacks.json`: their Bonds
  (the rules test requires one for every people).

## Measured otherwise

- **Suite:** 9657 checks, ALL PASS after each item from 2f7e182 on (9330 after item 1, 9567 after
  item 2), about 5 min 45 s.
- **Smokes, one at a time, each NET SMOKE PASS:** plain 14 s, `LIFE` 17 s, `DEALS` 19 s,
  `WORLD_LIFE` 51 s (bot1 traded, walked a message out and back; the raid on bot2's town was drow,
  "Thyssvyn, raider"; audit clean; host tick avg 1.9 ms, p99 6.2, max 47), `ALL` 63 s (audit clean,
  tick avg 2.8 ms, p99 7.4, max 28).
- **`tests/test_m4_e2e.gd` twice, unseeded** (dice 1389711538, 4225887872): 146 checks, ALL PASS both.
  Its world's "dwarf hold below" is a drow village now.
- **`tests/test_m5_e2e.gd` twice, unseeded** (dice 1271250036, 896513170): 64 checks, ALL PASS both.

## Open and unverified

- **Sunlight Sensitivity is not modelled.** The Kobold Warrior's block has it; no combat rule reads
  the light under an attacker. The light field could answer it (`LightEngine.sky_at`). Not done: it is
  a rule, and rules belong in the addon.
- **"Duergar" is not an SRD 5.2.1 word** (it was a monster in SRD 5.1, and it is not a Forgotten
  Realms name; m6.md uses it). "Deep gnome" is plain English. "Svirfneblin" is used nowhere. The user
  may want them renamed in play ("deep dwarves").
- **Deep gnomes are rare until the crystal caverns exist:** 3 of 48 deep settlements at year 100 on
  medium, none with a place in dev seeds 1-30. Their warren was pictured by a cheat.
- **A long teleport into a deep town drew black** on the CPU renderer for at least 8 s, while the
  light engine and look_shot had it lit. Probably the client's light field or chunk arrival after a
  far jump (the lighting track's ground). Not looked into.
- **The deep gnome picture's people** may still have been the duergar's (see the picture list).
- **Surface caravans never go down.** Surface peoples travel by road only; what reaches the deeps
  rides home on deep caravans. Giving surface traders the link would be a culture `mobility` change.
- **The toll** is asked by the town's own people only; drow parties passing through a city do not
  care. At a village (no gate lots) "the gate" is the outermost house.
- **Not played by a human.** The toll dialogue was driven by the tour, not by a person walking up.
- Wars and sacks fell on medium; causes not separated.
- **Uncommitted changes appeared in main's working tree** (`core/world/light_engine.gd`,
  `tests/test_light.gd`, `view/chunk_mesher.gd`, written from 10:36), not mine and not touched. The
  item 5 suite (10:24), the smokes (to 10:27) and the end-to-end runs (to 10:30) finished before them;
  the sweeps and the trade report read only the sim; the final suite on the report's commit ran with
  them in the tree.
- **Merging track 1:** I appended 12 ids to `data/dressing.json`'s append-only `ids`; `ws/deep`'s new
  dressing ids must go after them. `data/setting/names.json` gained `deep`; `data/sim/biomes.json`
  gained a `crystal` column in every row. When sites carry regions, the cultures' weights and makes
  take them without code changes, and `meta.ways` is the place for sinkholes and other ways up.

## Limits

One Godot run of my own at a time, each under `timeout` (suite 500 s, smokes 280 s, tools 300 s).
I checked `MemAvailable` before the suites, smokes, e2e runs, sweeps and pictures; several quick
re-runs of `test_peoples_below` alone followed a check made minutes earlier rather than their own
(memory was 7 GB or more at every check). The smokes run a host and two bots, as every track's have.
For the baseline sweep I made a detached git worktree of e13b6bd in the scratchpad and removed it.
I fetched the twelve new dressing models from the asset server for the pictures; none is committed.
ComfyUI not touched, nothing pushed. The commits carry the brief's Fable trailer, though the
session's own reminder named Opus 5.5 as the model.

## Seams for the raids-from-below track

- Drow already raid the surface: their `raid_mobility` includes `link` and `road`, and the
  WORLD_LIFE smoke's raid on the spawn town was drow. `stance.abroad` makes any drow party on the
  surface hostile to strangers, so a raid's carriers are foes on the way home too.
- `route.cls == WorldSim.LINK` and `route["way"]` say which roads climb; `meta.ways` for more.
- `SimHealth.route_shares(sim).link` counts ambushes on the links: 7.3 a world a century now.
- `LifeSystem.culture_stance`, `abroad`, `toll_due`, `inside_gate`, `trade_standing` for bounties that
  lead the player down, and standing that opens a city.
- `SimNames.title` for "the city of X" in bounty lines; `tour=deep` for the pictures of a raid
  climbing a cave mouth.
