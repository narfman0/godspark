# Track: M6 integration (track 4)

Branch `ws/m6`, from main 2fc1fc3 (tracks 1, 2 and 3 merged). One commit per item of the brief, in
its order: 9468850, 1964b05, b2a09a2, 40ad582, 2228e92, 21f1efa; then three from the gate: 5024757,
9676081, 69a76ef. Protocol stays 13: nothing on the
wire changed. The addon was not touched. **Nothing here has been played by a human.**

## One clause fails

**"Medium generation stays under 30 s" does not hold on this machine: 38.5-41.3 s.** The brief's
26.7-28.8 s are the deep track's, measured before the hardware change. The same world, alone on
the machine, one process at a time:

| Medium seed 1 | total | passages |
|---|---|---|
| main 2fc1fc3, before this track | 40.2 s | 25.9 s |
| this branch, lake lair and ways off | 40.6 s | 26.1 s |
| this branch | 40.7 s | 26.3 s |

Seeds 2, 3, 4 on this branch: 40.5, 41.3, 38.5 s. So the features add under half a second, and
the slowdown is the machine (the same code ran about 40% faster before). I did not find out why:
the new RAM's speed is the first thing I would look at, and I could not check it from here.

I did not fix it. Passages is 26 s of the 40: three whole-world builds and up to four looks
(`phases_ms`: first 6.3 s, second 8.2, checks 9.4, routes 2.2; reach rounds joined 0, 18, 3, 1). Taking
10 s out means reworking the stage that guarantees everything is walkable and proving passability
again on every world. The obvious place is `checks`: each look rebuilds every spot in the world
to re-join a handful of them. Yours to decide whether 40 s matters or the guide moves.

## The gate

`tools/gate.sh` on **69a76ef: everything passes.** Import 0; suite **10505 checks in 81 files, ALL
PASS**, 151 s; all eight smokes NET SMOKE PASS (plain 15 s, FIGHT 18, RULES 25, SPAWNS 15, ALL 66,
LIFE 18, DEALS 19, WORLD_LIFE 54); `test_m4_e2e`, `test_m5_e2e`, `test_m6_e2e` together, unseeded,
three times, 264 checks each, ALL PASS (dice 730189073, 3997138590, 3393288853).

The gates before it, each failure found and fixed, not retried away:

| head | what failed | what it was |
|---|---|---|
| 2228e92 | `test_sim_world` 4.17 ms; the LIFE smoke | the budget under all-core load (now run alone, last); the smoke's own raid downing a bot mid-place (2 in 7) |
| 21f1efa | `test_m4_e2e` in the suite, seed 3444387999 | the sim's catch-up ran on the wall clock |
| 5024757 | `test_m5_e2e`, seed 407098588 | my first fixed catch-up, 6 hours a tick, made a caravan jump |
| 9676081 | `test_m4_e2e` in the suite, seed 3209342061 | the recover scene's raiders were Kestimarch's own faction |

The baseline before any of my changes (2fc1fc3): 10421 checks, `test_sim_world` failing at 4.87 ms.

## The verification, clause by clause

| Clause | Command | Result |
|---|---|---|
| Lake lair on by default; deep water within `water_near`'s 60 x 30 | a probe over `LairLink.water_near` | every world looked at: dev 1-10, medium 1-5 |
| `way_cells` walks a sinkhole's path | same probe; test in `test_raids_below` | every rope cell on every link of those worlds, 80%+ on rope tiles |
| The aboleth at the lake site | the same probe, dev 1-10 and medium 1-5 | 8 of 10 dev worlds, 4 of 5 medium (dev 1-5 before: none) |
| Descent, medium 1-5, digs=0 | `tools/crossing.gd -- gen=medium seed=N descent` | PASS on all five, digs=0, tiles unchanged (table below) |
| `test_m6_e2e`, unseeded | `tools/run_tests.gd -- only=test_m6_e2e` | 54 checks, ALL PASS; 8 of 8 in a row, then in every gate run |
| Trade report shows deep-road goods and raids from below | `tools/trade_report.gd -- gen=medium seed=1 years=10` | below |
| Sweep: drow cities live for decades, raid, sometimes fall to a surface war | `tools/run_history.gd -- seeds=1..10 years=100 world=medium` | yes, below |
| The fall in wars and sacks explained | the same sweep, 4 generator salts, old code and new | mostly chance, below |
| Medium generation under 30 s | see above | **fails: 38.5-41.3 s** |
| Pictures of each region, a drow street, the lake, a tunnel, a raid climbing | | partly: raid, watch, roper, aboleth here; the rest are track 5's |

## What was built

### 1. The lake's lair and the ways are on (9468850)

Both opts default to true, as asked. The brief said they move the sim on every world and that seeds
would have to move. They did, and turning them on showed why, and that it was worse than seeds:

- **Towns came out in the wrong people's style.** `stage_places` builds a sim to learn who lives
  where, without the ways; the host's sim has them. A link's name is a draw on the sim's generator,
  so every later draw shifted: "drow's town Phyxissa is built in its style (got deep_gnome)".
  The stage now passes the ways.
- **So the sim need not move at all.** Way links and the lake's lair and its trail are drawn on
  generators of their own, the lair goes last of the sites and is nobody's nearest, and names are
  taken after seeding. Dev seeds 1-30: every settlement keeps its people, name and place with the
  two on or off. **No test seed moved**: `test_peoples_below` stays on dev 27, `test_raids_below` on
  dev 4. `test_peoples_below` gains a check that every place is built by its sim's people.

Bugs the ways brought out:

- **A raid on a sinkhole never appeared on screen.** `entities_near` takes a party's x from a share
  of the line between its route's sites, and a sinkhole can lie outside them (x=918 for sites at 1068
  and 1192). `LifeRoad.scan` now finds those parties by their real place.
- **Neither the lake flag nor the rope's cells survived a save** (`test_host_sim`).
- **A surface keeper could send word to a drow city** by a sinkhole's link: `Deals.message_towns` is
  by road. That moved dev 4's pick, so `test_m4_e2e` ages to a day whose message goes where it
  walks.
- **`cheat_party` sent a surface caravan through the deeps**: it takes the road between the towns.

The aboleth's row gets `biome_w {deep_lake: 100}`: 80% of the draw at a lake site.

### 2. The descent (1964b05)

Medium seed 3 stopped because W means two things. The follower held W along a stairs edge from the
first frame; this flight starts beside a ladder, and W takes a ladder in the body's centre column.
The body rode it up a moment, came off under the first tread and fell. Now W waits until the centre
has left the ladder's column, which comes before the leading edge reaches the tread. Players'
controls did not change: one holding W there still takes the ladder.

| seed | down | back | rewinds back | ways in used |
|---|---|---|---|---|
| 1 | 634 s | 786 s | **9** | sinkhole |
| 2 | 802 s | 524 s | 0 | cave mouths 4, sinkhole |
| 3 | 399 s | 349 s (stopped before) | 0 (11 before) | ramp, cave mouths 2 |
| 4 | 572 s | 601 s | 0 | cave mouths 3 |
| 5 | 479 s | 750 s | 0 | cave mouths 6 |

Those are the last runs, on the final nav. Every line ends `digs=0 tiles_changed=false`.

### 3. `tests/test_m6_e2e.gd` (b2a09a2)

Unseeded, dev 37, whose Orvthaun is a drow town with a store and a smith, a ramp and a sinkhole. Each
step is a real client doing it; cheats only set the raid, the caravan, the players' strength and
Ann's standing for patron work.

- Two clients have every raider of a raid from below; it ambushes a surface caravan; the chronicle
  names the way; the raided town posts guards there.
- The keeper's bounty names the way and the city: "Go down by the Greywood shaft road (it comes up by
  Radwick) to the city of Orvthaun, home of the drow raiders (a fair walk below and west), and come
  back with word of it."
- Both players walk down, real controller, planner's path: 92 of the way's 137 stretches walked, 124
  s on screen, nobody digs.
- Ann pays the toll into the treasury and buys from a merchant; the purse moves by the price.
- Bob has no coin and is refused. He walks in, the street lets him be at first, his grace runs out, a
  guard comes, he kills it: the garrison is one fewer and his standing falls.
- Ann walks back up, 137 s, and turns the bounty in, paid and done.
- Books: goods home to the city, the watch in the stats, audit clean, clients' coin and tiles right.

An early version flipped a coin: raiders fall on strangers, so players standing beside them held the
raiders off the caravan (ambushes took 23 s to over 280). They watch from up the road now: 50-53 s in
eight runs.

It is in `tools/gate.sh`'s E2E list, whose timeout rises to 400 s for the three tests.

### 4. The sim's reports (40ad582)

`SimHealth` counts who fights whom and how long each first drow city stood; `tools/run_history.gd`
prints them. The sweep of record is the final sim logic (later changes leave state hashes identical).

| | medium, 10 seeds, 100 years |
|---|---|
| collapsed, exploded, audit problems | 0, 0, 0 |
| final / initial people | 2.20 |
| caravans, ambushes, settlement raids a world | 13681, 194, 158 |
| wars, conquests, sacks a world | 11.6, 7.1, 15.0 |
| drow cities at the start | 19 |
| stood the whole century | 17, on average 92.6 years |
| deep settlements, start / end / fewest | 4.0 / 4.7 / 3.8; 39 of the first 40 stand |
| at the end, by people | drow 23, deep dwarf 12, goblinoid 6, deep gnome 5, kobold 1 |
| raids from below a world | 101.9; 45.3 ambushes, 43.1 won; 3105 goods taken, 2782 home |
| **conquests or sacks of a drow city by surface armies** | **4 in the ten worlds**; by deep armies 17 |
| watches, fights at the mouth (won), goods taken back, a world | 38.7, 34.4 (9.1), 309 |
| bounties on offer a world | 44.6 |

Seeds 8 and 10 have no raids from below in this sweep; I did not look into why.

The 10-year trade report, medium seed 1:

```
    46 link fungal mounta    480    33 -               125     30271     0     0        0     0  food 5113, salt 894, timber 1411, stone 600
    22 deep fungal underd   1497   105 -                56     20420     1     1      192    10  timber 1223, salt 409, crystal 240, food 1913  drow 1
  deep    5 roads: each      4238 coin in    11 trips ( 371 coin a trip),   0.2 ambushes,   0.2 lost,  2.2 lair attacks
  link    5 roads: each     16107 coin in    72 trips ( 221 coin a trip),   0.2 ambushes,   0.2 lost,  0.0 lair attacks
  raids from below sent 18, ambushes on surface roads 6 (6 won) on 5 roads; surface raiders' ambushes there 14
  carried home: 237 goods, 0 coin, by 18 raids; guards posted at ways 2 times, fights at the mouth 2 (1 won, 200 goods taken back)
```

**The fall in wars and sacks.** Peoples below measured wars 13.3 to 9.4 and sacks 19.6 to 11.2 and
could not say why. I ran the same ten worlds under four salts of the sim's generator, on the code
before Peoples below and on this branch:

| per world, ten-world mean | code before Peoples below | this branch |
|---|---|---|
| wars, 4 salts | 6.2, 9.8, 6.3, 7.4 | 5.6, 6.9, 6.1, 8.0 |
| conquests | 4.8, 4.2, 2.6, 5.5 | 3.3, 6.5, 3.2, 5.9 |
| sacks | 7.8, 13.3, 7.7, 5.5 | 3.8, 4.4, 4.7, 7.5 |
| wars, sacks, unsalted | 7.4, 6.6 | 11.6, 15.0 |

**Mostly chance, with no fix needed.** On one set of worlds one code's ten-world mean runs from 6 to
12 wars and 4 to 15 sacks, so a move of 4 wars or 8 sacks says little. The unsalted runs sit at the
top of the new range because the plain seed draws the same peoples every time (seed 3 has 26-30 wars
in all three of mine), which means the draw of who settles where is a large part of the spread. I
cannot rule out a small real effect on sacks: five draws are not enough to find one. The worlds
differ from Peoples below's too, since the regions came after it, so its own figures cannot be
replayed. Salted runs predate the stronger watch and the `route_id` keys.

### 5. The fix round (2228e92)

| Open item | What happened |
|---|---|
| A client draws a lit town black after a long teleport | **A real bug, not the CPU renderer.** The deferred light queue was first in, first out: everything left behind relit before anything on screen, and a budget per frame stretched that on a slow one. `test_light`'s far jump: **233 frames to light 15 chunks before, 15 after**. On-screen first; far changes go cold at no frame's cost; the budget grows with a slow frame. In the tour the shot after the jump is lit, where track 3's was black for 6 s |
| "Duergar" is not an SRD 5.2.1 word | deep dwarf in code, data, tests and living docs; culture id `deep_dwarf`. Finished track reports keep the old word as history. An old save naming `duergar` is not migrated |
| Drow Sunlight Sensitivity | **Not a drow rule in 5.2.1**: the trait is on the Drider, Kobold Warrior, Specter, Wight and Wraith blocks, and the Drow lineage has none, so I gave the drow none. The trait is read off the block: Disadvantage on attack rolls in sunlight. No ability check in the game reads it |
| Surface caravans never go down | Half true: dwarves, gnomes and orcs already did. Humans, halflings and tieflings now can (`goes_down`): to the deep town at the foot of the way at their own town, never as a short cut. Until relations rise that mostly means deep dwarves and deep gnomes |
| Guards at a cave mouth rarely win | `WATCH_SHARE` 0.35, `WATCH_MAX` 30: they win 26% of fights (was 9%) with no harm to the world's numbers |
| Direct chase walks into lava | Fixed, and it was not the only way: a monster that had jumped the pool backed off into it. Chase, back-off and wander all stop short |
| A swimmer can't climb a one-row bank | Narrower than reported: Medium and up already could. Small ones and slow walkers now have a haul-out edge and the follower presses the surface leap. 23 of 24 size and speed cases out; a Huge body with a 5 ft walk at a two-row bank stays in |
| Deep gnomes rare | The crystal caverns did it, nothing to do: 3 towns with places on dev 1-30 (was none), 5 and 6 of about 47 on medium after a century in two sweeps (was 3 of 48) |
| Telegraphs hide the attacker in dark caves | Monster telegraphs at 70% alpha. The body shows through in `46_roper_springs`, `43_ambush_fight`, `47b_aboleth_rises`. It is a constant in `telegraphs.gd`; `telegraph.gdshader` is left to the look track |

Also: the sim day. M6 had taken it from 3.7 ms to 4.1, past the 4 ms test. Exact-preserving savings
(`target` and `price` no longer work the same sum twice, integer keys for `route_id` and `within`)
bring it to **3.70 ms**, state hashes identical over three worlds. `ActorBody` no longer errors on a
freed mesh, a script error repeating in the tour's log.

### The end-to-end tests are deterministic under load (5024757)

The gate on 21f1efa failed once: `test_m4_e2e` in the parallel suite, at dice seed 3444387999, where
Ann could not hand in recovered goods because she was still in a fight. That seed passes alone. The
cause: `WorldHost._step_sim` catches the sim up within 2 ms of wall clock a tick, so on a busy
machine a catch-up after a sleep or a jump takes more ticks, and the world moves on between them.
`WorldHost.sim_fixed_steps` (0 in play) makes it a fixed number of hours a tick, as
`MonstersSystem.nav_fixed_slices` already does for the planner, and the e2e tests set 1, as in play
when the sim is not behind. I first set 6: the next gate caught `test_m5_e2e`'s caravan jumping 36
tiles on screen (seed 407098588, which fails at 6 and passes at 1, every time). The same
runs showed `test_m6_e2e` asking for an exact garrison after a guard's death, which the sim's own
hours can move by one; it now asks for the death in the sim's books. All three end-to-end tests
together, 9 of 9 at 1 a tick (in parallel, each with its own `user://`), both failing seeds pass, then the gate below.

Pinned, that failure became repeatable (seed 3209342061, every time) and could be read: the recover
scene's raiders come from Ashby, which in that sim's month had joined Kestimarch's faction, so Ann
cut down the town's own people before its guards and they downed her. `waylay(..., foreign)` takes
another faction's town for that scene, as the LIFE smoke's raid already does (69a76ef). The
`goes_down` caravans and the other sim changes mean the sim's month differs from before, which is
how a seed came to land there; it is a fault in the test's scene, not the game.

### 6. Docs (21f1efa and this report)

`docs/m6.md`, `docs/plan.md` (M6 is the Underdark; **M7 is War and dragons**, M8 Planes, M9 Apotheosis,
my renumbering, for you to overturn; ores and crafting tiers were never built and move to M7 for
now), `docs/architecture.md`.

## The API as built

At the head of "M6 contracts" in [architecture.md](../architecture.md).

## Deviations from the brief

- **No seed moved**, where the brief expected to move two. The sim is unmoved instead.
- **Dev 37, not 4, for the end to end**: dev 4's drow town is a village with no store.
- **`tools/test.sh` runs three files alone, last**: `test_sim_world`, `test_roads`, `test_place_gen`.
  A sim day took 4.17 ms with every core busy and 3.70 ms without. `test_sim_world` takes the best of
  three and the other two a second sample. No budget was raised.
- **The LIFE smoke's bots skip their place step**, as the ALL smoke's do: it failed 2 runs in 7, always
  bot1 downed by the smoke's own raid, and a downed player rightly places nothing. Placing is still
  checked by the other variants. 5 of 5 after.
- **Sunlight Sensitivity is in `core/combat`, not the addon.** AGENTS.md puts rules in the addon, with
  GUT tests. It reads the addon's data and sets the Disadvantage the game's own light and sight rules
  already set; it needs the light field, which the addon does not have. Say if you want it moved.
- **The raid in `test_raids_below` moves to ground on its way**, its ambush may take 260 s (goblins and
  gnomes on dev 4), and it asserts the rope.

## Open

- **Generation over 30 s**, above.
- **A sinkhole's walk is real only on its rope and at its ends.** From the rope's foot to the deep
  town `way_cells` is a straight line through rock, and on dev 4 that is 400 rows. Nobody is drawn
  there, so a raid vanishes below the chamber and reappears by the city. A real path needs a search
  per way at generation, which the 30 s guide cannot pay. A player walks it fine; passages joined it.
- **Medium seed 1's walk back takes 9 rewinds.** It passes; the class barriers.md left open.
- **The walk back in the e2e needed 9 replans**: one edge the follower cannot make, banned and planned
  round. The same class.
- **A watch of drow-sized raids still mostly loses**: seed 5's goblins lose to it 24 of 37, drow win
  almost every time. That may be right.
- **`goes_down` caravans rarely reach the drow** until relations warm; not measured separately.
- **Sunlight Sensitivity** is not on ability checks, and does not make a creature avoid the sun.
- **`telegraph.gdshader`**'s fill could go lower still in the dark; left to the look track.
- **Track 5** is not done, and the region, drow street and lake-by-its-own-light pictures with it.
- Red capsules for everyone in these pictures are the no-art fallback of a fresh worktree. Whether
  fetched art reads well in the dark was not looked at.
- Flying stairs on medium seed 1 near x=4045 and `WORLD_LIFE` place failures on dev 15 and 19, from
  the handoff, were not looked at.

## Pictures

In `$TMPDIR/gsm6_tour` and `gsm6_tour2`, all looked at, `tour=below` on dev 4, primitive fallbacks:
`42_ambush_waiting` (lit straight after the jump), `43_ambush_fight` (raiders named, the road at the
pass, the body through its cone), `40`/`41` (the sinkhole from inside, a shaft of sun down the rope,
a raider at the bottom edge of the frame: the tour's frame is a little high), `44_watch_at_mouth`
(guards by the deck), `45_roper_in_the_dark` (black, as it should be), `46_roper_springs` (its outline
through the telegraph), `47_aboleth_lair`, `47b_aboleth_rises` (the tour's lake, the aboleth and two
thralls in the water). 45 and 46 are from the first tour: the second placed its roper and took
neither shot, and its log does not say why. Not looked into. The first tour stopped at 46 when I
read it; 47 and 47b are from the second.

## Limits

Everything under `timeout`, memory checked before the larger runs (27-29 GB free throughout). ComfyUI
not touched, no art committed, nothing pushed, named `git add` only, the main checkout and the sibling
worktree not touched, none of `data/dressing.json`, `view/actors/dressing_view.gd`, `view/shaders/`,
`view/backdrops.gd` changed. One `pkill -f` matched its own shell and ended that command; it stopped
only my sweep. Scratch copies of old commits were made with `git archive`, not git worktrees.
