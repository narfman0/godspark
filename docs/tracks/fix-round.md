# Track: fix round

Short fixes from the open issues of the M4 integration. Branch `ws/fix-round`, cut from main
7823013. One commit per item.

## 1. A talk refused as "far" from 1.2 tiles

Reproduced in `tests/test_m4_e2e.gd` with dice seed 7 and with a test, and the cause was none of
the three suspects.

`RemoteEntity.pos` moved only in `ClientWorld.present()`, and only a `Presenter` calls that. A
client with no view (the test rig, the bots) kept the position a person had when first seen. In
seed 7 the client thought the merchant stood at x 619.5; the host had him at 565. The test
walked up to the empty spot and was refused. The "1.2 tiles" was the test's own teleport, 1.2
from that spot, printed after the last attempt: the failure message described a moment after
the refusal. It now logs each attempt as it happens.

`advance()` now keeps `pos`, `flags` and `vel` of every remote, and `present()` only emits.
`tests/test_talk_reach.gd` fails on the old behaviour (checked by taking the line out).

The suspects, measured:

| Suspect | Result |
|---|---|
| The host's copy of the player lags | No. Running at a person and pressing E the frame the prompt shows, at 30, 60, 100, 150, 250 ms each way: always opened. At 250 ms the host's copy is 7.6 tiles off when E is pressed, but the request travels behind the inputs and arrives with them. |
| The person walked since the prompt | Not what happened here, but real at the edge of range: a person walks 5.85 tiles a second, and the 1 tile between prompt (4) and host (5) was 170 ms, less than the view's delay and a 70 ms round trip. Worked out from those numbers, not seen in a run. The host's range is now 6.5 (keep 8.5): room for 300 ms of round trip. A client sends E only with the prompt showing, so no one reaches further. |
| The two ends measure differently | No: the same centres. |

That still left the prompt promising more than the host would do: it did not ask about sight,
a fight of your own, being down, or hostility. So: `DealsTalk.reach` is one check for both ends;
`DealsClient.would_talk(id)` and `nearest_person()` are the prompt, and `CombatClient.in_fight`
tells it who has been fighting. The test puts a wall up, swings, and drops standing, and in each
case checks that the host refuses and the prompt is gone.

## 2. Why the end-to-end test needed fixed dice

`E2E_SEED=n` replays a story; without it each run picks a seed and prints it. The fixed 41 is
gone: **the test is unseeded now**.

| Unseeded failure | Seen in | Kind | What was done |
|---|---|---|---|
| "far" with the person elsewhere | seed 7 | game: `RemoteEntity.pos`, item 1 | fixed |
| Last raider never caught, 9 of 12 goods | seeds 1, 9, 10 | game | A raider flees at 25% hit points at the player's own speed, turns home after 6 s, sees the player and runs again, for as long as it is chased. Traced: players and raider 40 tiles up and down the road for 120 s. A creature now flees once, then stands for `flee_again_s` (45 s). |
| Defence came out "beaten" | seed 9 | game (cause inferred, see below) | Only a raid cut down on the road said who did it. A raid thrown back at the town now says `by: adventurers` when players' blows killed raiders; `defend` reads it from either kind, wherever they stood. |
| "and home along the road" timed out | seeds 5, 204, 208 | test | A chase ended further into town than the road starts; the walk stopped at the road's end and counted them as not there. |
| "far" six times, the merchant walking the street | suite, seed 3158431702 | test | The player walked to where a person had been when it set out, and they had moved on. It now looks again as it goes, as a player does. |
| Hand-in "fight"; the town hostile to its saviour | seed 310 | game | A guard felled a raider during the player's wind-up and the blow landed on the guard standing there: standing lost, the town hostile for a minute. A bystander was spared only while a live foe had traded a blow in the last 5 s. A swing at a foe, or a foe within 3 tiles of the aim, now counts. |
| Goods "missing" with all 12 held | seed 4 | unexplained | Not seen again; see below. |

None of this widened a tolerance, removed a check or added seeding. The one check touched is
`walk`: past the end of the road counts as there, which is what a player in town is.

| | runs | passed |
|---|---|---|
| Before, seeds 1-10 | 10 | 4 |
| After the flee fix, seeds 201-210 | 10 | 8 (both failures the walk) |
| After the walk fix, seeds 301-310 | 10 | 9 (seed 310, the stray blow) |
| After the stray blow fix, seeds 401-410 | 10 | 10 |
| The suite, one of its runs | 1 | 0 (the walking merchant) |
| On the final code, no seed given | 10 | **10** |

One Godot at a time, 37-44 s each on the last batch; its seeds are in no earlier list.

Fixing a seed does not freeze a story across commits: a change that takes a die roll more or
less shifts everything after it. So seeds 4 and 9 could not be replayed with their old stories.
The defence's rule is tested directly (`_fought_at_the_gate` in tests/test_life.gd), but that
this was what happened in seed 9 is an inference: the players had chased raiders past
`near_tiles`, as the flee trace shows they do. Seed 4's hand-in was not explained at all. The test
prints who holds what if a hand-in fails again.

No legitimate bad luck turned up that needed handling. The caravan's "3 of 8" did not appear: 64
runs, lowest 5 of 8 (8 of 8 in 52), all 100 of 100 cargo.

## 3. Name plates in a crowd

Plates stepped up over each other without a limit. `Nameplates.arrange(want, scale)`, pure and
tested, now places them: at most `STACK` (3) name plates high; whoever finds no room gets a short
bar with no name at its head, up to `BAR_ROWS` (3) rows, and past that nothing; the names are
lifted clear of the bars. The one under the cursor, players and ranked foes choose first, then
the nearest. Spread out, everyone keeps a name, however many. Twelve in a clump: 3 names, the
rest bars, under 200 px above the heads at 720p, against a tower to the top of the screen.

`Nameplates.fit` works: a long name is cut at a word and fits. Tested now, with one endless word
too. One bug beside it: "(down)" was added before fitting, so a long name lost it.

Looked at: `/tmp/claude-1000/fix-round-shots/24_raid_at_gate.png` (1280x720; capsules, this
worktree has no art).

## 4. Old news shown as new

A joiner was sent the last 5 chronicle lines (`CHRONICLE_ON_JOIN`) and the feed showed them.
CHRONICLE now says whether it is history (**protocol 8**). History reaches `cw.chronicle` and
`chronicle_history`; only lines from after the player arrived reach `chronicle_lines` and the
overlay. Each peer has `arrived_h`, so a sim still catching up as someone arrives is history
too (tested). L shows the last few lines when nothing is showing, history included.

"New" meant new to the player, and `RUMOUR_DAYS` (60) was all of history in a world aged 60 days.
It now also means under `DealsTalk.NEWS_DAYS` (7) old. Old talk is still told and marked on the
map, without the word, with "19 days ago" on the card (a season is 90 days, so "Year 1, spring"
said little). When all of it is old the speaker says so (`rumour_stale`) and the toast says "Heard
2 old stories". The window of 60 days and the selection, newest first, are unchanged.

Beside it: rejoining toasted "Heard N new things" for up to 12 known rumours, since the whole
list came through `rumour_heard`. It comes through `rumours_reset` now.

Looked at: `/tmp/claude-1000/fix-round-shots/01_arrival.png` (no lines over the view),
`04_rumours.png` (no "New", "19 days ago", "Nothing lately. Folk still go on about this:").

## Deviations from architecture.md

Protocol 8. Otherwise additions: `chronicle_history`, `rumours_reset`, `would_talk`,
`nearest_person` (architecture.md updated).

## Numbers

Smokes on the code of a71bcb4 (later commits are docs), host tick avg / p99 / worst in ms:

| Smoke | | avg | p99 | worst |
|---|---|---|---|---|
| plain | pass | | | |
| `ALL=1` | pass, audit clean | 3.2 | 7.6 | 25 |
| `LIFE=1` | pass, audit clean | 2.4 | 16 | 25 |
| `DEALS=1` | pass, audit clean | 1.5 | 6.3 | 25 |
| `WORLD_LIFE=1` | pass, audit clean | 3.1 | 8.1 | 44 |

`core/entity` is untouched. The suite is 4046 checks in 61 files, about 195 s.

## Open issues

In [docs/todo.md](../todo.md), "Fix round".
