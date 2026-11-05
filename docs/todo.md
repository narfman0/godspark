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

## M2 integration (gaps between the M2 tracks; `docs/tracks/` has the detail)

Wiring
- Monster `look` (slug, people, rank, scale) is not sent to clients: remote monsters draw as
  plain capsules. ENT_ADD or a monsters SYS message should carry it.
- Longarm (reach) and Mole (dig speed) are tags nobody reads: `TileEdit`, the host dig and
  the client's predicted dig still use the fixed reach and dig time.
- Tempo sparks and affix tags (swing recovery, cast while moving, no slowdown when hit) are
  not read by combat. Featherfall should reduce fall damage, not only fall speed.
- Combat should call `rules.player_dropped(e, crit)` for every hit on a player at 0 HP and
  `rules.heal(e, amount)` for healing at 0 HP; spell slots spent on the combatant must
  reach `Character.slots_left` so they survive saves and show on the sheet.
- When Rules rebuilds a combatant it must end with `items.outfit(e)`.
- `Character.capture` caps saved HP at the max without gear: gear that raises Constitution
  loses its extra hit points on save.
- A downed player can still place tiles. Movement limits from conditions (speed 0, prone,
  frightened) are enforced only by the player's own client.
- Rules and combat move players by pushing CORRECT events themselves; add
  `WorldHost.teleport(e, pos)`.

Mirrors the interface is missing
- Deeds are not sent to the client (the sheet and Knack cards count this session only).
- Answered choices (feats, fighting style, skills) are not mirrored, so the character
  sheet's AC, attacks and skills can differ from the host's.
- Temporary hit points are not mirrored. Cast refusals from the host are silent.
- Quick-spell assignments are saved locally (`user://ui.cfg`), not on the host.

Content and rules gaps
- 168 of 258 SRD magic items are text only; 63 more apply their main number all the time.
- 225 of 339 spells are refused (217 have no mechanics in the addon). No monster
  spellcasting, bonus actions, reactions or legendary actions. Shield is manual.
- No opportunity attacks, two-weapon fighting, grapple, thrown-weapon key, or class
  features such as Second Wind and Action Surge.
- Epic Boons and tool and language Knacks are recorded only. Nothing reads Bonds.
  Species and background are stored but not applied. The one SRD subclass per class is
  taken at class level 3 without asking.
- The XP scale (15) rests on an assumed kills-per-minute table: re-fit with
  `tools/xp_pacing.gd` once the spawn director's real rates are known.

Never played
- Nothing in M2 has had a hand on the controls: attack feel, telegraph dodging at real
  latency, hold-to-rest and revive timing, inventory drag, spell aiming, HUD at 1080p,
  whether three goblins should be this deadly at level 1.

