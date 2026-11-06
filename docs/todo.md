# Open issues

Collected from the track reports (`docs/tracks/*.md` have the detail). Roughly by priority.

## Before "Dig together" (M1) is done
- Nobody has played it. Keyboard and mouse play, the debug keys and the chronicle toggle,
  the feel of predicted digs and of correction blending, and a second human client are all
  untested; so is anything off localhost (NAT, latency, packet loss). The hardening pass
  ([tracks/hardening.md](tracks/hardening.md)) closed every other M1 gap it listed.

## Net and host
- Light for a cold chunk is now spread over frames, but one chunk is still one 8 ms flood
  on the main thread (worst frame about 9.5 ms while walking). A worker flood with
  commit-on-main would remove it.
- Object removal under a predicted dig is not predicted (the tree goes one round trip
  later).
- The host thread is GDScript on a `Thread`: anything touching the host from the main
  thread must go through `NetSession.host_call` / `with_host`, and HostEndpoint signals must
  be connected deferred. Not tried on Windows or macOS.
- Startup can show a 130 ms frame while models load (GltfCache).

## Movement
- Burrow is a stub. Climbers cling to walls only (no ceilings).
- Host checks client movement by bounds only; replaying inputs would close it.

## World generation
- Five surface biomes (M5, [tracks/biomes.md](tracks/biomes.md)): the sim's biome economy,
  per-biome dressing, sky and spawning are later tracks, and mountains and rivers are not
  barriers yet. Caverns sit in one row along the deep road; in medium and large worlds most
  of the deeps and all of the nadir is plain noise caves.
- Routes are checked open, not walkable under gravity. No liquids. One ascent per world.
- Tile ids must stay below 256 during generation.
- Dressing: trees are sparse on bumpy ground (about one per 80 columns) and kept off
  settlement grounds; ceiling objects are never placed; one biome's set only.

## Places
- Towns are short of their full building list where the ground is narrow (100-240 columns).
- The skin is furniture and props; Synty wall and roof panels are not used. No per-culture
  piece scale (halflings use human pieces).
- Ladders in buildings until the Traversal `stairs` tile replaces `H`.
- Ascent and portal route paths are graded walks since the passability pass (a few rough
  where grading found no way).
- Conquest keeps the old style; ruins keep no name for arrival notices.
  ([tracks/places.md](tracks/places.md))

## Rendering
- No textures, parallax, liquids or real lights. Blocks read flat.
- Sources combine by max; only torch-strength lights match SRD radii exactly.
- Night is SRD Darkness for the rules (sun 0.04) but drawn moonlit (the view's floor of
  0.25). Deliberate; revisit when darkvision and stealth land.

## Art
- Modular hero gear swapping is not built: part files carry only the bones they use, so
  parts need re-skinning onto a master skeleton (plan at the end of assets/survey.md).
- No pack has a climb, ladder or swim clip. Attack, hit and death clips load but have not
  been looked at. Feet slide a little at full run speed.
- The Meadow pack's trees are broken as cooked on the server (leaf materials lost).
- Exported builds need `assets/*` in the export filter (untested).

## Strategic sim
- The host owns and steps a `WorldSim` and clients see its chronicle, but nothing is
  materialized (M4). Materialization needs: a map from each sim route to its tile path, a
  frozen flag per materialized entity with fold-back writers, per-entity seeded dice, and
  hooks for what players cause (escorts, cleared lairs).
- Its calendar ("Year 2, spring") is its own, not tied to the world clock's day count.
  Chronicle news is slow on small worlds (about 10 entries a game year on dev; a game year
  is 120 real hours).
- Tuned on synthetic strips; only spot-checked on real worldgen output (seed 7, 80 years:
  healthy). Travel times may need retuning against real route lengths.
- Tick cost is 2.1 ms per simulated day at about 130 settlements (target 2 ms); trade
  planning dominates.
- Food relief reaches under half of famines. Raider-heavy deep worlds grind each other
  down. Combat ignores spells, breath weapons and regeneration. No alliances or revolts.
- Invented names come from `data/sim/names.json`; `data/setting/names.json` is still empty.
  One should become the single source.

## Life (M4) ([tracks/life.md](tracks/life.md))
- Rough routes (most ascents and portal routes): people fall behind and are put back.
- Wagons are a primitive cart; no cart model fetched.
- The `ALL=1` smoke runs with `places=0`: bots' placing is flaky in a peopled town.

## Deals (M4) ([tracks/deals.md](tracks/deals.md))
- The stopgap panel is gone: the M4 Interface track built the dialogue, shop, quest log, map
  and standing screens ([tracks/m4-interface.md](tracks/m4-interface.md)).
- Escort work is rare: it needs a caravan already leaving that day (the sim plans caravans
  every 5 days). A sim hook to announce departures a day ahead would make it regular.
- Recover covers raiders still abroad; goods already at the raiders' camp have no quest.
- Patron work: the hunt is offered and taken in a test; its completion and sieges are not exercised end to end
  (the end-to-end test covers message, bounty, escort, defend, relief, recover and a patron's gift).
- Quest coin and XP, shop markups, the rumour window: first guesses, unbalanced against loot.

## Interface (M4) ([tracks/m4-interface.md](tracks/m4-interface.md))
- Portraits are role icons on faction colours; people's looks are not used.
- Work marks preview the day's offers until someone asks (may differ if the town changes first).
- Rumour map marks are not saved; the
  standing history is per session (Life does not mirror reasons).
- Not judged by a human: map hover and drag, shop Shift-click and nudge, marks in a crowd,
  the copy's tone; not looked at at 1920x1080.

## M2 after the integration pass ([tracks/m2-integration.md](tracks/m2-integration.md))

Open from the integration pass
- Caves (M4 passability): see "Passability" below (point-to-point and every site met; joins,
  speed and Large climbers open). Ladders still stand in for roots.
- Traversal: no rope item in shops or loot yet (crafted from supplies, two in the kit); the
  player picks stairs_r or stairs_l by item (no auto-facing). Ore now sells at towns
  (Deals) and rope is on store shelves.
- Monsters do not attack downed players (brains skip them); a hit on a downed player comes
  only from areas, falls and other incidental damage, and counts as a failed death save.
- Steady (cast_move) wins back a casting slowdown that is 1.0 in data/combat.json (none, as
  played); turning a slowdown on is a feel decision. Surefoot shrinks pushes.
- Temporary hit points are mirrored to the owner only (STATUS), not to other players.
- The attack slot (hotbar 1) is a convention of Inventory.add; nothing stops a player putting
  blocks there by hand.

Content and rules gaps
- 168 of 258 SRD magic items are text only; 63 more apply their main number all the time.
- 225 of 339 spells are refused (217 have no mechanics in the addon). No monster
  spellcasting, bonus actions, reactions or legendary actions. Shield is manual.
- No opportunity attacks, two-weapon fighting, grapple, thrown-weapon key, or class
  features such as Second Wind and Action Surge.
- Epic Boons and tool and language Knacks are recorded only. Nothing reads Bonds.
  Species and background are stored but not applied. The one SRD subclass per class is
  taken at class level 3 without asking.
- Lantern, Owl and Dowser tags are for the view and have no reader yet; Silver Tongue,
  Hearthfriend and Beastfriend wait for trade, reputation and monster bonds.

Never played (beyond the first session)
- Attack feel, telegraph dodging at real latency, hold-to-rest and revive timing, inventory
  drag, spell aiming, HUD at 1080p, whether day packs by the spawn are now too easy.

## M4 after the integration pass ([tracks/m4-integration.md](tracks/m4-integration.md))
- `kill` deeds count twice per typed kill: `add_deed("kill")` and the `kill:<type>` aggregate in
  `Knacks.add_deed`. Deed thresholds may be tuned to it; left alone.
- Recover ends at the raiders' town stock: the pointer goes there, but they are usually hostile
  and no quest asks you to raid it. Goods bought elsewhere still satisfy the quest.
- Host hitches: a town appearing is about 22 ms in one tick, a monster's plan up to about 45 ms
  (budget 33 ms). One soak showed a single 57 s tick inside Rules that two more soaks did not
  repeat; the cause was not found (a stalled machine is the likeliest guess, not established).
- Slow memory growth in the soak, about 5 MB a game day after warm-up; not traced.
- Stair treads a little apart from any flight appear in caverns (passages); seen once by eye.
- A tilted cart on a 45-degree road still looks stiff; no cart model.
- XP pacing rests on assumed fight lengths; only play can check it.

## Fix round ([tracks/fix-round.md](tracks/fix-round.md))
- The talk prompt cannot know a grudge: the host alone holds it, so a person with one still
  answers "hostile" after a prompt. Everything else the host refuses, the prompt now checks.
- A person walking away at the prompt's edge is in reach for 300 ms of round trip. Past that
  they can answer "far"; the range was worked out from the numbers, not played at real latency.
- `NEWS_DAYS` (7), the plates' `STACK` (3) and `BAR_ROWS` (3), `flee_again_s` (45): first
  guesses. Fleeing once is a rule of every creature that flees, not only raiders; not played.
- Past the bars' rows a plate shows nothing: a raid of a dozen in one spot has some fighters
  with no bar until they spread out or the cursor is on one.
- The chronicle's history is the last few lines, by L. There is still no screen for it.
- Not seen again, so not explained: one run in which a party held all 12 goods and the hand-in
  said "missing" (before the fixes; that story no longer exists). A caravan with 3 of 8 was
  never seen in 64 runs here (lowest 5 of 8); if it comes, the test will fail on it and it
  needs sorting.

## Passability ([tracks/passability.md](tracks/passability.md); met: point-to-point, every site, the follower)
- Met: Medium point-to-point 94% (target above 85%); every site and route end on foot in 10
  of 10 dev and 3 of 3 small worlds (nav graph); real-body site walks 94%; the follower
  takes 96% of planned cave paths without replanning, and `test_monster_nav`'s follow bar is
  back at 9 in 10 (Medium; Large 3 in 4).
- Joins are not clearly fewer: rope + ladder 520 -> 441 per dev world, about 750 joins in all;
  still thin vertical lines on the map. Next: joins that serve several pockets by design (one
  switchback stair or long rope per pit); slopes in place of shafts cost point-to-point share.
- Generation is slower, not faster: dev 2.5 s, small 8.6 s (2.1 s and 6.1 s before, same
  machine; target about 1.3 s and 3.5 s). Two or three whole-world analyses in GDScript loops;
  needs incremental re-analysis or a native step.
- Large climbers 33% (target 43%): joins are Medium-sized; no Large-sized joins or size marks.
- Rough deep routes: 5 of 80 on dev, 1 of 42 on small (grading found no way along the line).
- A few Passer moves per world still disagree with the nav graph; the guarantee is checked
  by `tools/passability_sweep.gd`, not inside the stage.

