# Track: raids from below and the deep life (M6, track 3)

Worktree `ws/raids`, cut from main at 2b03fb9. Items 4 and 5 of [m6.md](../m6.md): a deep city's
raiders climb a way up to rob caravans on the surface roads and carry the goods home, the surface
answers with guards at the way and a patron's bounty, Life shows it all; lairs of the deeps with
bosses (the aboleth with Legendary Actions and charmed servants, ropers and cloakers in the dark),
and burrowers that really dig. Track 1 (deep biomes, `ws/deep`) had not landed when this was built
or when it was rebased: there is no deep lake in any generated world, so the aboleth was built and
tested against a lake placed in a test world, and pictured in a lake the tour digs.

## What was built

### 1. Raids upward (c1924c6)

- **The record is the raid party.** A raid from a deep settlement whose target is a surface road
  is a raid from below (`SimBelow`): it must reach the road by a link route on its path (worldgen's
  ascent, a way from `meta.ways`), and `SimBelow.mark` writes into its plan the way's route id
  (`below`), its kind (`way`: `ascent` for worldgen's ramp, else the meta.ways kind) and its
  schedule (`out_t`, `due_t` at the road, `back_t` home, sim hours). It walks up, waits on the road
  (the sim's ambush machinery: `ambush` state, `AMBUSH_DAYS`), takes a caravan, and walks home,
  where `SimEconomy.return_home` puts its cargo and coin in the city's books as for any party
  (`SimBelow.came_home` counts it, chronicle `raid_home`).
- **Which road.** `SimConflict.route_targets` weighs roads as before: coin a trip of the factions it
  would rob, the chance one passes in 12 days, `PINCH` for a pass (+1.0) or a ford or bridge
  (+0.35), less for distance. For a deep settlement `SimBelow.weigh` keeps a surface road only when
  a way up lies on the path to it, multiplies it by the culture's `raids_up` (new in
  `cultures.json`: drow 1.6, goblinoids 1.3, 1 for everyone else), and by `GUARDED` (0.35) when the
  way is watched. Deep roads and settlements are weighed as before. `SimBelow.targets(sim, s)` lists
  them richest first, for tests and tools.
- **The surface answers.** When an ambush from below ends (`SimConflict.ambush_outcome`), the raided
  caravan's home town (or the town at the way's top) posts a watch at the way: `sim.way_watch[way] =
  {home, faction, culture, n, n0, until, since}`, 15% of its soldiers (3 to 12) for 90 days, renewed
  by the next ambush; saved (`way_watch` in the sim's dict only when there is one). A raid from below
  going up or down a watched way meets the watch at the mouth, 70% of the time, once a leg
  (`SimBelow.tick_parties`, `SimCombat`): beaten raiders lose what they carry to the guards' town.
  When the watch ends, what is left of it goes home.
- **The bounty.** Quest kind `below` (`DealsQuests`, `data/deals/quests.json`): patron work, offered
  by the keeper or priest of a town whose caravan was robbed by raiders from below in the last 60
  days, while the raiders' city stands. Its goal names the way and where it comes up, and the city by
  its deep title: "Go down by the Bitterway shaft road (it comes up by Pellenmarch) to the spired city
  of Thyssrak, home of the drow raiders (a fair walk below and east), and come back with word of it."
  It is ready when a party member stands in the city, or when adventurers cut down that city's
  raiders (`raid_repelled` by adventurers); turned in at the giver's town as other work.
- **The chronicle** says it: "drow raiders from Qelesh came up the Flintbarrow shaft road and
  ambushed a caravan from Wexwell on the Thornmarch road; ...", "Kestimarch posts 9 guards at the
  Hollowmire shaft road, where raiders came up from below", "the guards of Brenmarch at the
  Emberwater shaft road met drow raiders from Zaeraethaun coming up and drove them off (5 raiders and
  2 guards fell)".
- **`tools/trade_report.gd`** has a last section: surface roads with ambushes from below, those
  against surface raiders' ambushes on them, raids sent, goods and coin carried home, watches and
  their fights.

### 2. A raid from below on screen (22fbd9d, and LifeBelow in c1924c6)

- LifeRoad already shows any party along its route's tile path, so a raid from below walks up its
  way (the ascent route's own path), out along the road, waits, and walks home. A way from
  `meta.ways` has no meta route: `LifeBelow.way_cells` draws one, deep site to the way's bottom, up to
  its top, on to the surface site (`route.top` and `route.bottom` are now kept on the sim's link).
- Raiders are named by their people's role for their block (`LifeRoad.raid_role`, the cultures'
  `roles`): a drow raid shows "Kyrvyn, raider" (spy, bandit), "Orvrak, scout", and a mage or priest
  when the recipe draws one.
- The watch at a way's mouth (`LifeBelow`, `life.below`): the watch's people stand at
  `LifeBelow.mouth(h, way)` (meta.ways' top, else the last cell of the ascent's path open to the
  sky), as many as the sim counts (at most 6), each keeping a light; one who falls is one fewer in
  the sim (`SimBelow.watch_guard_killed`).
- Standing is as track 2 left it: a drow abroad falls on strangers, and killing one there costs no
  standing (tested again here).
- Two players: over the wire (`NetRig`, dev 4) both clients get every raider of the same raid; the
  ambush is fought on screen and settled by Life into the sim as an ambush from below; the raiders
  turn for home and walk back toward their way.
- `LifeSystem.cheat_below(city, road, at, frac, n)`: a raid from below put on its way up or waiting
  on its road (tests, tour).

### 3. Lairs with bosses (e84341d)

- **Lair rows by ground** (`data/sim/lairs.json`): `biomes` (the aboleth sea only in `deep_lake`),
  `bands` (the purple worm, CR 15, only in the nadir), `biome_w` (ooze pits and pudding sumps 3 times
  as likely in `fungal`, 2.5 in `deep_lake`), `charmed` ([slug, min, max]: the aboleth's 2 to 4
  thralls, warrior-infantry and scouts, counted among the lair's members). The sim draws a lair as it
  always has, on its own generator, with the old weights and members; where the drawn row may not
  stand, or the site's biome is one a row favours, the lair is drawn again by the new rules on a
  generator of its own (seed, site, hour). So every existing world draws its lairs, and its places,
  exactly as before (the first version changed dev worlds and failed four seed-bound checks; see
  deviations).
- **CR by depth band** as the spawn director has it: every lair of the caves and the deeps leads with
  a creature in its band's CR range (tested), the purple worm waits for the nadir.
- **The aboleth** comes out in the nearest deep water to its site (`LairLink.water_near`), a boss in
  its lair (`in_lair`: four Legendary Action uses), its thralls as people of a species picked by a
  hash (make_npc), named "Khelgrim, thrall of Glimmerdeep Sea", in its pack, each Charmed by an
  effect whose source is the aboleth.
- **Legendary Actions** are the addon's (submodule commit 15df7eb): `MonsterActions.parse_legendary`
  reads the stat block's `legendary_actions` into `Combatant.legendary` (`uses`, `lair_uses`, options
  with `kind` attack or action, the `action` named, `heal` dice, `requires`), `legendary_available`,
  `use_legendary` (spends, heals), uses back at `start_turn`; 6 GUT tests, the addon's 629 pass.
  `CombatSystem.legendary(e, foe)` takes one between the creature's own actions, at most one every
  `legendary.gap_s` (2 s, `data/combat.json`): Lash swings one Tentacle; Psychic Drain, first while
  hurt and only while it holds someone Charmed or Grappled (`holds_any`: its thralls count), uses
  Consume Memories at the foe and heals 1d10. The brains call it when their own attack is not ready.
- **Ropers and cloakers in the dark** (`brains.json dark_ambush`): placed at the nearest spot of the
  light field's DARK near the lair (`LairLink.dark_near`), they wait (lurker) hidden while their cell
  is DARK (`CombatSystem.set_hidden`: the SRD's Invisible from Hide, an effect that ends when they make
  an attack roll; clients get it as a CONDITION event), and spring when a player comes within the
  trigger (6 tiles). Lit (a torch set down by one), it is seen. Once sprung it is seen again 1.5 s
  later (`reveal_s`), after its first blow, which lands unseen.
- Grick nests and darkmantle roosts are the caves' rows as they were.

### 4. Burrowers (034b51b)

- `Burrow` (`core/monsters/burrow.gd`) is a way of moving: the burrower digs the cells its body
  needs one column on toward its goal, up or down a row at most (`next_cells`), then walks into them;
  only natural tiles give (`brains.json burrow.natural`: ids 1-3, 13, 16-63 and 118, so never
  bedrock, water, roads, buildings or bridges, and new worldgen tiles in 16-63 count), removed with
  `TileWorld.set_fg`, the host's tile path to every client. What it digs is owed as a player's dig of
  it gives (`Items.tile_drop`: rubble, or the ore), dropped in piles of 8 behind it. At most
  `cap_per_min` tiles a minute per creature (default 120; purple worm 240, bulette 150); when a
  column would pass the cap it waits.
- The monsters system gives a burrower (a `burrow.creatures` row and a Burrow speed) a Burrow and
  takes away its planner digging (`rec.dig` 0), so all its digging is capped.
- **The purple worm** wanders through the rock (`_tunnel`): to a point within 48 tiles of home (14 up
  or down), a cavern when one of eight tries is open ground, at half pace; its tunnels stay, and in
  the test one joins two caverns 59 tiles apart. It fights with its SRD Bite and Tail Stinger
  (Multiattack) as any monster, digging toward its foe when rock is between them.
- **The bulette** waits (lurker) and senses by tremorsense (now read by every brain: what moves on the
  ground within range), springs at 40 tiles, goes down into the rock and along beneath the ground
  beside its prey (`under_tiles` 3 under the floor), opens a shaft up through the floor next to it,
  and comes out on the far side of it with its SRD Deadly Leap (a Dexterity save, 3d12 and Prone).

### 5. Pictures

`game/ui/world_tour.gd` `tour=below`, the real client and UI, offline host with cheats:

```
tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=4 \
    world=DIR world_tour=DIR timeout=280 tour=below
```

In `/tmp/claude-1000/-home-narfman0-workspace/7cf54a79-3f3e-43af-87e7-ba72c23eb7f8/scratchpad/raids_below_shots/`,
looked at (from four runs; the last ran out of its 280 s before the worm, so the worm is the third
run's):

- `40_raid_climbing.png`, `41_raid_out_of_the_mouth.png`: the ascent ramp of Kyryszhar under a swamp
  forest, a dark tunnel climbing left to right below the grass; the raiders on the ramp, named
  ("Ssilvyn, raider", "Xalaequor, scout", "Phyxissa, raider"), drawn as red silhouettes and swing
  arcs: they had fallen on the player standing at the ramp (a stranger abroad), "Raiders of House
  Kyrydril" on the plate. The bodies are red, not the Synty drow; I did not look into whether that is
  their hit flash or a missing look.
- `43_ambush_fight.png`: the Bittermire road over the pass, a grey mountain slope with pines, the
  caravan "of the Deepforge of Kheluthum, bound for Dolakdek" fighting at the road (its escort with a
  spear, the drow off to the right under a cliff), goblin warriors of the spawn director further down
  the slope. The shot before it (`42`) was black for 6 s after the jump there, as track 2 saw.
- `44_watch_at_mouth.png`: the mouth of the ramp in a hillside, four guards of the town under it by
  their lamp, grey figures with spears, the raid's own way out.
- `45_roper_in_the_dark.png`: black, with the chronicle lines of the raid and the watch: the roper is
  in the light field's DARK and nothing of it is drawn. `46_roper_springs.png`: the same black, the
  "Roper" plate and its swing coming at the player from the dark.
- `47_aboleth_lair.png`: the lake the tour dug on a deep road, blue water under a brown rock roof lit
  by six lamps, "Boss Aboleth" in the water with its tentacle's reach drawn as a long red cone, four
  thralls standing in the water below it, the player on the shore.
- `48_purple_worm_tunnel.png`: a tunnel through brown rock lit by the torches the tour set in it, the
  piles of rubble the worm left along its floor every few tiles, the worm itself a red blob at the left
  edge (the primitive fallback; no purple worm model), 160 tiles dug in 25 s with its cap lifted for
  the picture.

## The contract as built

```gdscript
# sim (core/sim/sim_below.gd, class SimBelow)
SimBelow.pull(culture) -> float                        # cultures.json raids_up, 1 when absent
SimBelow.way_on(sim, path) -> link route id | -1; way_kind(sim, rid); surface_end / deep_end(sim, rid)
SimBelow.weigh(sim, s, cands, mask, dist) -> cands     # SimConflict._maybe_raid, deep settlements
SimBelow.targets(sim, s, hungry := false) -> [{route, weight, way, crossings}]   # richest first
SimBelow.launch(sim, s, rid, n := 8) -> SimParty; mark(sim, p, way); is_below(p); way_of(p)
SimBelow.post_watch(sim, sid, way); tick_watches(sim); tick_parties(sim); watch_guard_killed(sim, way)
SimBelow.WATCH_DAYS 90, WATCH_SHARE 0.15, WATCH_MIN 3, WATCH_MAX 12, GUARDED 0.35, WATCH_MEETS 0.7
party.plan: below (way id), way (kind), out_t, due_t, back_t; met_out, met_home (watch met)
sim.way_watch: {way id: {home, faction, culture, n, n0, until, since}}   # saved when not empty
chronicle: ambush + below, way, wayid, home, vhome; way_watched; watch_fight; raid_home
stats: raids_below, below_ambushes, below_wins, below_taken, below_coin_taken, below_home,
  below_goods_home, below_coin_home, way_watches, watch_fights, watch_wins, watch_recovered
ledger rows: below, below_taken; SimHealth.below(sim); SimHealth.observe(...)["below"]
route (meta.ways links): top, bottom (kept through a save)
WorldSim.lair_weight(row, site); lairs.json biomes, bands, biome_w, charmed [slug, min, max], species
# deals
DealsQuests kind "below": target {city, way, faction, mark, mouth, found}; quests.json below
# life (core/life/life_below.gd, life.below)
LifeBelow.way_cells(h, rid); mouth(h, rid) -> Vector2; open_sky(world, cell); actors_at(h, way)
LifeRoad.raid_role(culture, slug); LifeSystem.cheat_below(from_site, rid := -1, at := "way", frac, n)
entity meta sim {kind: "watch", id: way, role: "guard"}
# monsters and combat
CombatSystem.legendary(e, foe) -> bool; holds_any(e); set_hidden(e, on); is_hidden(e)
CombatSight.field_category(p)            # the light field alone, no carried torches
data/combat.json legendary.gap_s; brains.json dark_ambush, reveal_s, burrow {natural, cap_per_min,
  pile, rate_per_tile_s, min_rate, creatures: {slug: {cap_per_min, rate_mult, wanders, wander_tiles,
  wander_y, wander_s, pace, surfaces, trigger, under_tiles, leap}}}
Burrow.new(slug, stats); step(host, e, goal, dt) -> PlayerInput | null; dig(host, e, cells, dt);
  next_cells(world, body, dir, dy); shaft_cells(world, body, top); natural(id); is_burrower(slug)
MonsterBrain.burrow, surfaced, leaps; dark_ambusher(); LairLink.water_near(h, p), dark_near(h, p, slug),
  lair_def(l); entity meta in_lair, thrall
# addon (submodule 15df7eb)
Combatant.legendary; MonsterActions.parse_legendary, legendary_left, legendary_available, use_legendary
```

## Deviations

- **The raid record is the party.** No separate raid record: a raid party with `plan.below` already
  has a home, a target route, its path through the way, and now a way and a schedule; the sim moves,
  fights and saves it as before. Raids from below are not new in kind: the drow raided the surface
  through the link before this track (track 2's WORLD_LIFE smoke). What is new is that a road needs a
  way up, the pull, the guards, the record and the bounty.
- **Under-routes are not ways up.** The ranges' under-routes join surface to surface and are not in the
  sim's graph; the ways up are the link routes (worldgen's ascent, and meta.ways when the deep track
  fills it). A cave mouth is the top of a link.
- **The bounty is found, not killed.** "Bounty" asks the party to find the city (stand in it) or to see
  its raiders cut down; it does not count kills in the city. Nothing else in Deals counts kills by
  faction, and a party asked to kill drow in their own city would also be asked to break the toll.
- **The tunnel is the body's box.** A purple worm is Gargantuan, 7 by 7 tiles here: its tunnels are
  7 tiles high (17.5 ft), not the SRD's 10-foot diameter; anything smaller would not let it through.
- **"Bulette diggings" are not a lair.** My first table had a bulette lair in the caves; it changed
  which lairs every existing world draws. Bulettes come from the spawn director as before (caves and
  surface, CR 5).
- **Lair rows by ground draw again on their own generator** rather than reweighting the sim's own
  draw: with a reweight, dev seeds 3 and 4 placed other towns (worldgen's places stage seeds the sim)
  and four seed-bound checks failed (`test_dressing` swamp dressing 19 of 20, `test_m5_seams` stone
  at 2 both ways, `test_place_keeper` no laid-out site, `test_sim_biomes` meadow against forest town).
  None was changed; the redraw keeps every world as it was.
- **Tremorsense is now a sense for every brain** (it was not read at all): what moves on the ground
  within range is noticed. It changed no existing test.
- **Hidden is the SRD's Invisible**, from an effect that ends on the attack roll (5.2.1 Hide). The view
  does not hide invisible creatures yet (it is the main checkout's): a hidden roper is unseen by
  combat's rules and by brains, and drawn by the client if lit. In the dark it is not drawn anyway.
- **Pictures change the world by cheats**: a trade history for the roads (a world just begun has
  sent no caravans), the lake (dug by the tour), the aboleth sea moved to it, the worm's cap lifted.

## Numbers

### The sweep: medium, 10 seeds, 100 years

`tools/run_history.gd -- seeds=1..10 years=100 world=medium cache=DIR` (track 2's cached worlds), 266 s.

| seed | raids from below | ambushes (won) | goods taken | home, goods, coin | watches | fights at the mouth (won) | bounties | by |
|---|---|---|---|---|---|---|---|---|
| 1 | 112 | 68 (65) | 4531 | 110, 4506, 3758 | 55 | 47 (3) | 68 | drow 63, kobold 5 |
| 2 | 74 | 23 (23) | 2346 | 74, 2346, 1681 | 18 | 12 (0) | 23 | drow 23 |
| 3 | 2 | 0 | 0 | 2, 0, 0 | 0 | 0 | 0 | |
| 4 | 122 | 66 (64) | 6557 | 116, 6339, 5205 | 59 | 52 (8) | 66 | drow 66 |
| 5 | 75 | 14 (14) | 2040 | 75, 2040, 764 | 14 | 11 (0) | 14 | goblin 14 |
| 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 7 | 160 | 99 (95) | 6602 | 156, 6459, 7777 | 78 | 62 (7) | 99 | drow 88, goblin 11 |
| 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 9 | 170 | 93 (87) | 7387 | 161, 7271, 5822 | 71 | 61 (5) | 89 | drow 84, kobold 9 |
| 10 | 37 | 9 (6) | 211 | 31, 0, 0 | 9 | 11 (11) | 9 | drow 6, kobold 3 |
| **a world** | **75.2** | **37.2 (35.4)** | **2967** | **72.5, 2896, 2501** | **30.4** | **25.6 (3.4)** | **36.8** | drow 330, goblin 25, kobold 17 |

- Per world per 100 years: 75 raids from below go out, half wait on a road that a caravan passes,
  and 35 rob one; 2896 goods and 2501 coin come home to the deep cities (97% of what they took; the
  rest died with raiders or was taken back at the mouth: 71 goods a world). Seed 10's watches won all
  11 of their fights and its raiders brought nothing home.
- Three worlds have none: no raiding people below with a way up (seeds 6 and 8), or a city whose
  roads up lead only to friends (3).
- **Bounties taken** cannot be counted by a sweep: no players. "Bounties" above is how many a raided
  town's patron would have offered: an ambush from below on its caravans while the raiders' city
  stood, 36.8 a world, each on offer for 60 days.
- The watch rarely wins (3.4 of 25.6): 3 to 12 guards against a raid of up to 30. It costs a raid 30
  to 50 raiders over a century and makes the way weigh a third as much while it stands.

Whole worlds, against track 2's own sweep ("after") on the same cached worlds:

| | peoples below | this track |
|---|---|---|
| final / initial | 2.21 | 2.21 |
| collapsed, exploded, audit problems | 0, 0, 0 | 0, 0, 0 |
| caravans a world | 14913 | 14984 |
| ambushes, settlement raids | 158, 137 | 165, 141 |
| wars, conquests, sacks | 9.4, 6.0, 11.2 | 8.9, 5.6, 9.4 |
| deep settlements start / end; first 40 standing | 4.0 / 4.8; 38 | 4.0 / 4.5; 37 |
| pass roads: ambushes a road | 25.6 | 28.3 |
| links: ambushes | 7.3 | 7.3 |

### Trade report, medium seed 1, 10 years

```
== Raids from below on surface roads (deep raiders up a way), against surface raids
    id from   to     crossings        value   ambus   below   taken surface
     6 swamp  swamp  -                57210       1       1       1       0
     8 swamp  meadow ford             64402       1       1       1       0
    11 meadow meadow -                56715       1       1       1       0
  raids from below sent 10, ambushes on surface roads 3 (3 won) on 3 roads; surface raiders' ambushes there 12
  carried home: 120 goods, 0 coin, by 10 raids; guards posted at ways 3 times, fights at the mouth 2 (0 won, 0 goods taken back)
```

### Tests

- `tests/test_raids_below.gd`, 86 checks: a drow city with a way up weighs the pass road
  over a flat one at the same coin and a richer flat road over the pass; 4000 of its raid decisions
  (60 from below, the richest road twice as often as the pass); the plan's way, kind and schedule; no
  surface road without a way up; drow and goblins pulled, duergar not; a raid from below walks up the
  way to the road, waits, takes a caravan (the chronicle says it came up the way), walks home, and
  every unit and coin it carried is in the city's stores, its raiders back in the garrison; the raided
  town posts a watch from its own garrison, the way weighs less, the patron's bounty names the way and
  the city and is ready when a player stands in the city, the watch ends and comes home; raids
  climbing a guarded way meet the watch; a watch through a save; on dev 4 the drow
  city's way has a mouth and a walk, a raid on it is shown with its roles, hostile to a stranger, seen
  by both players, a raider killed on the surface costs no standing, the watch stands at the mouth with
  a light and a guard who falls is written back; over the wire, two clients and one raid, the ambush
  fought on screen and settled as one from below, the walk home.
- `tests/test_deep_life.gd`, 84 checks: the lair tables by ground and band, CR in band,
  300 draws at a lake site (aboleth seas, 2 to 4 thralls each) and on rock (none); the aboleth in the
  water of a test lake, a boss in its lair with four uses, three thralls Charmed by it in its pack
  drawn as people, Lash, Psychic Drain first while hurt and healing, four uses then none, all back at
  its round, a thrall killed written back; a roper in a black cave hidden (Invisible) where the field
  is DARK, unseen by a player with a torch, waiting at 12 tiles, attacking at 3 and seen after, and a
  torch set down beside another lights it; a purple worm under a cap of 40 digs 40 tiles in its minute
  and waits, every tile gone from the rock and sent as a tile change, then tunnels 59 tiles to the next
  cavern, its tunnel open behind it and its rubble on the ground, stopped by a built wall; natural
  tiles; a bulette senses a walker 30 tiles off, goes under the floor, comes up beside it with its
  Deadly Leap, which lands.
- The addon: `tests/test_legendary_actions.gd`, 6 GUT tests; all 629 pass.

## Measured otherwise

- **Suite** ALL PASS: 9737 checks (item 1), 9748 (2), 9811 (3), 9832 (4); item 5 changed no core
  path a test takes but SimHealth's new `below` (read-only), and was checked by the suite on the
  rebased head: **9832 checks, ALL PASS**, rebased on main dc631d5 (the deep track had not landed).
- **Smokes on the rebased head, one at a time, each NET SMOKE PASS:** plain 14 s, `LIFE` 20 s,
  `WORLD_LIFE` 51 s (audit clean), `ALL` 63 s (audit clean, host tick avg 2.9 ms, p99 7.3, max 28).
- **`test_m4_e2e`, `test_m5_e2e` once, unseeded** (dice 1575322071 and 550092597): 210 checks, ALL PASS.
- **The addon's GUT suite:** 629 tests, all pass.
- No existing test was changed or removed, and no test seed moved.

## Open and unverified

- **The deep lake is mine, not worldgen's.** No generated world has `deep_lake` until `ws/deep` lands;
  then aboleth seas appear at its lake sites without code changes, and `LairLink.water_near` finds the
  water (two rows deep or more, within 60 x 30 tiles). If the deep track's lake lies farther from its
  lair sites than that, the aboleth comes out on dry ground.
- **meta.ways have no path of their own.** `LifeBelow.way_cells` draws a straight walk through a way's
  bottom and top; a raid's people walk it with monster nav and are put back beside their point when
  they fall 40 tiles behind (as on rough routes). When the deep track gives its ways a path, use it.
- **Sinkholes and `descent`** (the deep track's) are read only through `meta.ways`.
- **The view does not hide the hidden.** Clients get the Invisible condition; drawing a hidden roper
  faint or not at all is the view's.
- **Raiders draw as red shapes** in the pictures; not looked into.
- **The far jump draws black** for some seconds on the CPU renderer (track 2's open issue), so the
  tour comes in from 240 tiles and waits.
- **Watches seldom win.** If the surface should hold its ways, WATCH_SHARE and WATCH_MAX are the
  handles.
- **The purple worm's tunnel is 7 tiles high** (its box), and a worm in the nadir has nowhere to go up
  but rock: worlds with nadir lair sites were not looked at.
- **Not played by a human.**

## Limits

One Godot of my own at a time, each under `timeout` (suite 500 s, tools and pictures 300 s), memory
checked before each (several quick targeted test runs right after a check). No ComfyUI. Nothing
pushed. Worldgen, `data/tiles.json`, `tools/crossing.gd` and the view's shaders not touched. The addon
change is a commit in the worktree's submodule clone (15df7eb, on a794bc2): it is not in the local
addon repository the worktree script clones from, so merging this branch needs that commit fetched
from this worktree's submodule first.
