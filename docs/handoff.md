# Handoff, 2026-11-07

Paused mid-M6 for a hardware change. This is where everything stands and how to pick it up.

## Main is green at `59cf480` (plus this handoff commit)

`tools/gate.sh` on `59cf480`: 10432 checks ALL PASS (408 s), all eight `tools/net_smoke.sh`
variants (the FIGHT smoke failed once in the gate with no log kept, then passed 3/3 alone;
the gate now keeps every smoke's logs), `test_m4_e2e` and `test_m5_e2e` unseeded three times.

Submodule `vendor/godot-srd-addon` is at `15df7eb` (Legendary Actions), which is also
`main` of `~/workspace/godot-srd-addon`.

## What landed since M5 (newest first)

| Commit | What |
|---|---|
| `59cf480`… (11) | **M6 track 1, deep biomes and the descent** (`docs/tracks/deep.md`): fungal, crystal, deep-lake and magma regions in worldgen with their own rock, caves and light tiles; a swimmable sealed lake; lava that burns and walls nav; sinkholes and cave mouths as recorded ways down; `tools/crossing.gd descent`; spawning by region; regions on the map once seen. `meta.biomes` gained underground rows: read the surface strip with `BiomeIds.strip`. Protocol 13. |
| `832dacb` | Raids are handed to Life at a town's buildings (`LifeSystem.town_dist`), not within 48 tiles of its square: raiders no longer teleport from the gate to the square. The LIFE smoke's cheat raid walks in from 40 tiles out. |
| `fbe0384`… (6) | **M6 track 3, raids from below and the deep life** (`docs/tracks/raids-below.md`): deep cities raid surface roads by their ways up, guards posted at the mouth, `below` patron quests, raids on screen for two clients, aboleth/roper/cloaker/ooze lairs by ground, legendary actions (addon `15df7eb`), burrowing purple worm and bulette, `tour=below`. |
| `dc631d5` | LIFE smoke's cheat prefers a raid from another faction (same-faction raiders meet no guards). |
| `2b03fb9` | **Foreground corners black or white**: the soft mesher's cut corners had no wall behind them; `_soft_cells` draws one. `tools/corner_shot.gd` renders every corner kind. Also: the light flood lights rock in inner corners. |
| `5f090e8`… | **M6 track 2, peoples below** (`docs/tracks/peoples-below.md`): drow, duergar, deep gnome, kobold and goblin cultures; deep settlements with kits; deep roads as trade; drow toll and stance. |
| `e13b6bd` | **Lighting** (`docs/lighting.md`): per-tile sky/block fields, real Godot lights with shadows, no free player light. |

## M6 state (`docs/m6.md`)

Tracks 1, 2 and 3 are merged. **Not started:**

- **Track 4, integration.** The brief I had written (an agent was launched on it and stopped
  before it changed anything):
  1. Turn on what the deep track left off: `opts lake_lair`
     (`core/world/worldgen/stage_sites.gd:143`) and `opts ways` (`gen_context.gd:271`) become
     default. They move the sim on every world 2048 wide, so seed-bound checks in
     `test_peoples_below` (dev 27) and `test_raids_below` (dev 4) must move, with reasons.
     Then verify on generated worlds: an aboleth lair at a lake site has deep water within
     `LairLink.water_near`'s 60x30, and `LifeBelow.way_cells` walks a sinkhole's `path`. On dev
     seeds 1-5 the sim never picked the aboleth for the lake site: favour lake-only lairs there.
  2. The descent end to end: `tools/crossing.gd -- descent` on medium seeds 1-5, digs=0.
     Medium seed 3's walk back stops under the portal ramp's treads at (2092, 831), a
     planner/follower disagreement on a stair edge onto a ramp-hole tread: fix the cause.
  3. `tests/test_m6_e2e.gd`, unseeded: two clients watch a raid from below (`cheat_below`)
     ambush a surface caravan; a `below` patron quest names the way and the city; a player
     follows the way down on foot to the city, pays or is refused the toll, trades or fights;
     the sim's books agree (goods home, guard post set, bounty resolved); audit clean.
  4. `tools/trade_report.gd` medium seed 1, 10 years shows deep-road goods and raids from
     below; a sweep (medium, 10 seeds, 100 years) shows drow cities living for decades,
     raiding, sometimes falling to a surface war; the peoples-below sweep's unexplained fall
     in wars/sacks explained or fixed; medium generation under 30 s (now 26.7-28.8 s).
  5. Fix round from the three reports' "Open" lists: deep gnomes rare until crystal caverns;
     surface caravans never go down; a client draws a lit town black for 8 s or more after a
     long teleport (likely a real fast-travel bug: chunk/light arrival on the client); guards
     at a cave mouth rarely win (`WATCH_SHARE`/`WATCH_MAX`); a swimmer can't climb a one-row
     bank; direct chase walks into lava; "duergar" is not an SRD 5.2.1 word (rename); drow
     Sunlight Sensitivity not modelled; raider swing telegraphs (large red hatched cones) hide
     the attacker in dark caves.
  6. Docs: `docs/m6.md` "Where it stands", `docs/tracks/m6-integration.md` with evidence per
     verification clause, `docs/plan.md` M6 state and what M7 is, architecture contracts.
- **Track 5, the look below** (M6 deliverable 6, no track has covered it): dressing per
  underground region (`data/dressing.json` `where.biomes` can name regions now), the lake's
  light (its water reads near black; only the lumen moss lights the shores), fog of the deep,
  the view hiding creatures combat marks Invisible (ropers and cloakers), drow architecture
  from the kit. The fungal picture from the deep track is a grey floor with small cyan caps:
  it needs the dressing to read as a forest.
- Then the user plays M6.

If both tracks run at once: worktrees `tools/new_worktree.sh m6` and `look-below` (branches
`ws/<name>`), the look track must not touch worldgen, the sim, Life or sim tests; integration
must not touch `data/dressing.json`, `view/actors/dressing_view.gd`, the view's shaders or
`view/backdrops.gd`. Merge by rebase onto main then `git merge --ff-only`.

## How to verify anything

- `tools/gate.sh` (about 12 minutes; `E2E=test_m4_e2e,test_m5_e2e,test_m6_e2e tools/gate.sh`
  once the M6 test exists). Logs in `/tmp/godspark-gate`.
- Targeted: `godot --headless -s res://tools/run_tests.gd -- only=test_life,test_raids_below`.
- Pictures: `tools/soft_godot.sh -s res://tools/look_shot.gd -- gen=medium seed=1 ...`,
  `tools/corner_shot.gd`, and the world tour (`game/main.gd` host option `world_tour=DIR tour=deep` or `tour=below`, see `game/ui/world_tour.gd`). Look at them.
- Machine rules in `AGENTS.md`: one Godot per agent, 2.5 GB free before each, everything
  under `timeout`, never start ComfyUI, never commit art, named `git add`.

## Known flakes and rough edges

- The FIGHT smoke failed once in a gate run without a kept log (now kept); 3/3 alone.
- The LIFE smoke was a coin flip before `832dacb` (bots killed by veterans on the square);
  4/4 after. If it flakes again, its logs are kept with `KEEP=1`.
- `WORLD_LIFE` bots fail placing on dev seeds 15 and 19 (since M5).
- Flying stairs on medium seed 1 near x=4045 (since M5).
- The raids-below pictures draw raiders as large red hatched swing cones over a barely lit
  body; cosmetic, listed in the fix round.

## Waiting on the user

- Playtest feedback owed on: hit-stop, roll distance, swing arc loudness, GPU frame time with
  dressing, and now the deep regions, the descent, drow cities and raids from below.
- Open M6 questions in `docs/m6.md`: drow hostile until standing is earned (default), duergar
  and deep gnomes included (default), how deep the first pass goes in levels (default class
  level 10).
- Memory settings: AGENTS.md's one-Godot-at-a-time and 2.5 GB rule was for the 32 GB machine
  with ComfyUI running; with the new RAM the suite could be split by file (`tools/test.sh`
  takes `JOBS`; 10-12 processes took it from 150 s to about 30 s when tried) if the user says
  so.
