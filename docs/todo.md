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
- One surface biome. Caverns sit in one row along the deep road; in medium and large worlds
  most of the deeps and all of the nadir is plain noise caves.
- Routes are checked open, not walkable under gravity. No liquids. One ascent per world.
- Tile ids must stay below 256 during generation.
- Dressing: trees are sparse on bumpy ground (about one per 80 columns) and kept off
  settlement grounds; ceiling objects are never placed; one biome's set only.

## Places
- Towns are short of their full building list where the ground is narrow (100-240 columns).
- The skin is furniture and props; Synty wall and roof panels are not used. No per-culture
  piece scale (halflings use human pieces).
- Ladders in buildings until the Traversal `stairs` tile replaces `H`.
- Ascent and portal route paths are rough (ramp holes) until Traversal's passability pass.
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
- Watched caravans and raids move at the sim's pace (about 0.04 tiles a second): decide
  whether parties need time compression on screen (it would make watched history differ).
- Needs Places data: anchors and route paths; on today's worlds people spread over the site
  and parties stand on straight lines (in rock on shaft roads).
- Items has no trade-good rows (dropped cargo is coin); returning cargo is not a deed yet.
- The view ignores `look.light` (guards' torches) and the wagon look.
- The `ALL=1` smoke runs with `places=0`: bots' placing is flaky in a peopled town.

## M2 after the integration pass ([tracks/m2-integration.md](tracks/m2-integration.md))

Open from the integration pass
- XP curve shape: with the director's measured kill rates no single `XP_SCALE` meets the
  pacing target (early 3-6 min and the 90s an hour). At 8: levels 2-5 take 4.7-7.5 min but
  level 50 ~8 min, the 90s ~6 min, ~10 h in all. The deep bands need their own XP divisor
  (or fewer, slower deep spawns); the deep kill rates rest on assumed fight lengths.
- Caves (M4 traversal, partly met): worldgen stage `passages` joins cave regions; Medium
  walkers reach 69% of cave pairs 40 tiles apart (48% before; target 85%) and 94% of sites
  from the spawn on the nav graph (every site in 5 of 10 dev worlds; the nadir portal is the
  usual miss). Left: NavFollow fails jumps and long walks (27% of real-body site walks
  arrive); the 64-tile search window misses ways that go round; Large climbers lost share
  (two-wide shafts); a few deep sites; generation is +1.0 s on dev, +3 s on small; joins are
  dense (hundreds of short ladders and ropes per world). Ladders still stand in for roots.
- Traversal: no rope item in shops or loot yet (crafted from supplies, two in the kit); the
  player picks stairs_r or stairs_l by item (no auto-facing); ore trade goods have no
  buyer until Deals.
- Monsters do not attack downed players (brains skip them); a hit on a downed player comes
  only from areas, falls and other incidental damage, and counts as a failed death save.
- Steady (cast_move) wins back a casting slowdown that is 1.0 in data/combat.json (none, as
  played); turning a slowdown on is a feel decision. Surefoot shrinks pushes.
- Scripted melee on uneven ground connects rarely (the ALL smoke bots: a few hits in 20-70
  swings); check whether players feel the same on slopes (arc vs body height).
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

## Test flakes
- `ALL=1 tools/net_smoke.sh` failed once in four runs on main after the Places merge ("no
  bot waited in bed for the other"), then passed three times. The bots' bed timing is
  real-time dependent; make the wait check robust or the bots deterministic.

## Passability (the user asked for a world passable without digging; targets not met yet)
- Point-to-point trips through caves: 69% for a Medium walker (target above 85%); Large
  climbers fell from 43% to 27%.
- Every site reachable on foot from the spawn: 94% of sites, all of them in 5 of 10 worlds
  (target: every site, every seed). Misses: the nadir portal, sometimes a deep settlement.
- The monster path follower fails jumps on long paths: real-body site walks succeed 27% of
  the time, and `test_monster_nav`'s bar for following found cave paths was lowered from 80%
  to 70% (traversal) and to 60% at the Places merge (13 of 19). Fix the follower, then
  raise the bar back.
- The planner's 64-tile window misses ways that go the long way round.
- Places stamps settlements after the passages stage runs: check passages near settlement
  edges, and re-run the roads stage's deep routes, which were all flagged rough.
- Worldgen now takes about 1.8 s for a dev world and 5.4 s for a small one.

## Life integration
- Watched caravans and raids move at the sim's pace, about 0.04 tiles a second: a caravan is
  nearly a standing camp. Decision: the sim's travel speed becomes an on-screen pace (a
  wagon about 1.5 tiles a second, people on foot about 2.5), so a trip between neighbouring
  towns takes minutes and can be escorted; retune the sim's sweep after.
- The view draws neither wagons nor guards' torches. Dropped cargo is coin only (Items has
  no trade-good rows beyond ore).

