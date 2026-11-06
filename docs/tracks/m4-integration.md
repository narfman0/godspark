# Track: M4 integration

The pass that proved the living world works as one thing. Branch `ws/m4-integration`, cut from
main 615af8a. One commit per item.

## 1. The end-to-end test and the WORLD_LIFE smoke

`tests/test_m4_e2e.gd`: two fighters over the loopback on 1024x512 seed 4 (two halfling towns on
a 203-cell road, a dwarf hold below, lairs), all systems, director off, host dice seeded (the
story repeats exactly). 144 checks, 38 s. They arrive (notice, people at posts), talk, buy and
sell (the books move by what changed hands), hear a rumour with a place on the map, then:

| Work | How it is really done | What is cheated (scene only) |
|---|---|---|
| message | both walk the road there and back (24.5 s each way) with a steering input on the client | nothing |
| relief | food bought in the far town, carried back, delivered; stock and price move | the famine |
| bounty | oozes killed with real swings; the sim's lair is cleared | players put at the lair; hammers given (oozes are immune to slashing) |
| escort | held until they are beside it, 281 s at its pace, beside it 99% of the time, ambush fought, arrives with 6 of 8 and 100 of 100 cargo; far stock grows | the caravan, the raiders |
| defend | fought with the guards; repelled in the chronicle; standing rises | the raid |
| recover | raiders killed on the road, drops picked up, walked home | raiders with cargo, the ambush line |

Then a patron's gift, a smith's piece, host and clients agree, save, load, rejoin: quests,
rumours, seen places, standing, racks sold today, coin and pack came back; the audit is clean.

`WORLD_LIFE=1 tools/net_smoke.sh`: real processes; bot1 trades, walks a message out (a trail
across country on dev seed 3: the route is not stored) and back, a raid and a caravan reach
bot2's town; DEALSCHECK, `HOSTSTATS audit: clean`. Tick avg 3.2 ms, p99 8.5, worst 44.

What it exposed:

| Bug | Fix |
|---|---|
| Escort judged "most of its cargo" by people: cargo is sold on arrival | `caravan_arrive` records `plan.brought`; the quest compares with the load at offer |
| An ambush settled, then the same parties' next blow opened it again (more loot, another chronicle line) | `LifeRoad.settled` |
| Two players sharing a recover could not hand in: goods go to whoever touches them first | turn-in pools the party's goods at the town |
| A defence won beyond 30 tiles of the town came out "beaten" | a raid cut down by adventurers counts; "there" is within near_tiles |
| Recover went dead when raiders got home | it points at their town (the goods are in its stock) |
| `fight_step` skipped raiders by design (not hunted) | optional chooser |

Most other early failures were the test's own (y grows upward; lambdas copy locals; oozes are
immune to swords; only four offers a day, made at the first ask).

## 2. XP and loot

The toast was real: `on_kill` paid full XP to every player within 24 tiles, whoever killed
what, guards and townsfolk included, and every death dropped loot. Now, decided:

- only foes pay (`Life.xp_foe`: wild, raiders, people hostile by standing). A grudge does not
  count, so hitting a townsman first does not make him worth XP. Standing still falls in Life.
- a player's landed blow: full XP, shared in full with players within 24 tiles, kill deeds.
- only others' blows: a quarter, no deeds, to a player in that fight (dealt or took a blow in
  the last 10 s and within 24 tiles); nothing to one who stood by.
- no blows at all (a fall): as a player's kill, as before.
- loot by the same test. Life still drops a laden raider's cargo whoever killed it.

Tests: `_credit` in tests/test_deals.gd.

## 3. XP pacing

Rates re-measured (`spawn_sim kill=hunt from=settlement`, seed 4): surface day 166 XP/min (M2:
80), night 300, caves 4309, deeps 9617, nadir 54475, the deep ones scaled to assumed fight
lengths of 5, 10 and 20 s. `data/rules/xp.json` divides a kill by the band where it died; fitted
by `tools/xp_pacing.gd -- measured fit`. XP_SCALE stays 8. Quests in the model: two jobs an
hour at about 100 XP, 3.3 XP/min, undivided (it matters only in the first levels).

| | target | before (flat) | after: caves 3, deeps 2.5, nadir 9 |
|---|---|---|---|
| levels 2-5, min each | 3-6 | 2.8-3.5 | 2.8-3.5 |
| level 25 | | 3.2 | 9.4 |
| level 50 | ~20 | 6.6 | 21.1 |
| level 75 | | 4.1 | 35.8 |
| the 90s | ~60 | 6.6 | 58.9 |
| to level 100 | ~40 h | 7.8 h | 40.0 h |
| reach L10 / L25 / L50 / L75 | | 0.5 / 1.5 / 3.7 / 5.4 h | 0.5 / 2.6 / 8.8 / 19.0 h |

The model assumes the player fights in the band the level anchors name. Not played.

## 4. Rough edges

Plates shorten long names at a word and take INFO heard before the view existed; the id path
("lantern_eater") was already closed by M2 (`names`), and no raw id was reproduced. Plates
follow a turned caravan (`LifeSystem.resend`, tested). The escort's `where` is resent every 1.5 s
when it has moved 3 tiles (tested). Shops buy shelf camp gear at `sell_camp` 0.5 of list, into
its good. A paid room is a bed within 12 tiles (`in_paid_room`, the E prompt). Carts rest on the
road and swing round with the horse. In the end-to-end escort, its people and wagons were on a
floor or stairs at 85% or more of sampled moments.

Melee (`tests/test_melee_slopes.gd`, a still goblin, aim at its middle): the arc itself was fine
on slopes and stairs up to 2.6 tiles across. The real miss was a ledge two up: the blow's line
ran from the chest and hit the edge, and the target then had full cover. Blows now go from the
chest or the shoulders. Down a 45-degree slope, 3 tiles across (3 down) is out of a 2-tile reach,
as it should be. The M2 bots' misses: `fight_step` stopped by x alone and swung at air; it now
closes by box gap.

## 5. Soak

`tools/soak.gd -- days=3` (dev size, seed 3, aged 60 days): real ticks, no clients, two players
moved along route cells, 108000 ticks, 230 legs. A raid or caravan every six game hours.

| | |
|---|---|
| Script errors | 0 (one crash found and fixed: `schedule` at a site that is not a settlement) |
| Tick | avg 2.5 ms, p99 5.6, worst 45 (Monsters; budget 33) |
| Memory static | 109 -> 137 MB; 122 at 200 s, about 5 MB a game day after that |
| Entities | 18-66, no trend; monsters 16-64, Life 0-40, drops 1-14, parties 0-2 |
| Audit, books | clean; shown people never over the sim's counts (checked every 100 s) |
| Chronicle | 7 new lines in 3 days |
| Script | 442 talks, 20 buys, 20 sells, 565 swings |
| Quests | 16 offers seen, 16 accepted, 7 done, 0 lapsed, 0 failed, 9 open at the end |

Before the outbox was drained the run showed 109 -> 322 MB: the tool's fault (no endpoint), not
the game's. One earlier run showed a single 57 s tick inside Rules (`sys 1`); the following full
run, instrumented, did not repeat it, worst 45 ms. Cause not found.

## 6. Pictures

`tour=journey` beats 23-27 in `/tmp/claude-1000/godspark-m4/`, looked at. Monsters of
monster-forge were not fetched (`bootstrap.sh --no-monsters`), so oozes and the like are red
capsules. Seen and fixed: the cart went ahead of a horse walking left. The deep settlement was
reached by teleport in the picture (on foot only in the nav sweep); the rope and the stairs are
stills, not a descent. Full 27-beat tour not rerun.

## Numbers

Host tick in the smokes: plain 0.5 avg / 3.6 p99; FIGHT 0.5 / 2.0; RULES 0.6 / 2.2; SPAWNS 3.5 /
23; ALL 2.9 / 6.4; LIFE 2.4 / 15; DEALS 1.4 / 4.4; WORLD_LIFE 3.2 / 8.5 (ms). `core/entity` is
untouched, so traces cannot have moved (`git diff 615af8a -- core/entity` is empty).
