# Open issues

Collected from the track reports (`docs/tracks/*.md` have the detail). Roughly by priority.

## Before "Dig together" (M1) is done
- Nobody has played it. Keyboard and mouse play, the debug keys and the chronicle toggle,
  the feel of predicted digs and of correction blending, and a second human client are all
  untested; so is anything off localhost (NAT, latency, packet loss). The hardening pass
  ([tracks/hardening.md](tracks/hardening.md)) closed every other M1 gap it listed.
- No inventory: placing is unlimited.

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
