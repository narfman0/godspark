# Open issues

Collected from the track reports (`docs/tracks/*.md` have the detail). Roughly by priority.

## Before "Dig together" (M1) is done
- Nobody has played it. Keyboard and mouse play, and a second human client, are untested;
  so is anything off localhost (NAT, latency, packet loss).
- Digs and places are not predicted on the client: they show one round trip later.
  Host corrections snap with no smoothing.
- A listen host ticks inside the render loop, so a slow frame rate slows the host. Move the
  host tick to a timer or thread.
- Light for a newly seen chunk is computed on the main thread (about 8 ms): hitches when
  scrolling into new areas.
- Each client allocates the whole world (about 380 MB for a large one, plus light). Needs a
  sparse `TileWorld`; that also stops unloaded chunks reading as open air.
- Clients are not sent `world.meta` (biomes, sites).
- No inventory: placing is unlimited.

## Movement
- A fast diagonal fall just below a ledge top slides down the side instead of landing.
- A body spawned inside solid tiles is not pushed out.
- Burrow is a stub. Climbers cling to walls only (no ceilings).
- Host checks client movement by bounds only; replaying inputs would close it.
- Dig times: `WorldHost` adds 1e-6 s per tick to hide float32 hardness rounding; fix in
  `TileEdit` instead.

## World generation
- One surface biome. Caverns sit in one row along the deep road; in medium and large worlds
  most of the deeps and all of the nadir is plain noise caves.
- Routes are checked open, not walkable under gravity. No liquids. One ascent per world.
- Tile ids must stay below 256 during generation.

## Rendering
- No textures, parallax, liquids or real lights. Blocks read flat.
- Sources combine by max; only torch-strength lights match SRD radii exactly.

## Art
- Modular hero gear swapping is not built: part files carry only the bones they use, so
  parts need re-skinning onto a master skeleton (plan at the end of assets/survey.md).
- No pack has a climb, ladder or swim clip. Attack, hit and death clips load but have not
  been looked at. Feet slide a little at full run speed.
- Dressing objects are scattered by the demo only; worldgen should place them and the host
  should replicate them (record format proposed in tracks/assets.md).
- The Meadow pack's trees are broken as cooked on the server (leaf materials lost).
- Exported builds need `assets/*` in the export filter (untested).

## Strategic sim
- Not connected to the running game yet: the host does not own a `WorldSim`, and nothing is
  materialized (M4). Materialization needs: a map from each sim route to its tile path, a
  frozen flag per materialized entity with fold-back writers, per-entity seeded dice, and
  hooks for what players cause (escorts, cleared lairs).
- Tuned on synthetic strips; only spot-checked on real worldgen output (seed 7, 80 years:
  healthy). Travel times may need retuning against real route lengths.
- Tick cost is 2.1 ms per simulated day at about 130 settlements (target 2 ms); trade
  planning dominates.
- Food relief reaches under half of famines. Raider-heavy deep worlds grind each other
  down. Combat ignores spells, breath weapons and regeneration. No alliances or revolts.
- Invented names come from `data/sim/names.json`; `data/setting/names.json` is still empty.
  One should become the single source.
