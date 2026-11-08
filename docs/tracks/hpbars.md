# Track: hpbars (quieter hit point bars; keep Synty as much as possible)

Branch `ws/hpbars`, 2026-11-08. Two asks from the user:

1. Less screen business. A creature's hit point bar should show only while it is hurt, and fade
   out after its last change.
2. Keep Synty as much as possible; monster-forge only replaces the others.

The user's binding decisions from this brief are in docs/plan.md "Decisions":
- one project, no addons for game features (Sunlight Sensitivity stays in `core/combat`)
- about 40 s for medium generation is accepted (docs/m6.md and docs/tracks/m6-integration.md
  updated)
- licensing is not a concern for now
- keep Synty as much as possible
- quieter hit point bars

Pictures are not in git. They are under `~/.cache/hpbars/` on the dev machine, and the file names
below refer to them.

## Summary

- Hit point bars:
  - A bar appears on a hit point change, holds 2.5 s, then fades out over 1.5 s. Every change
    restarts it.
  - A full-health creature shows nothing, even when engaged or in a fight.
  - Ordinary monsters get a short bar with no name. Ranked foes and other players carry their name
    and the rank frame while the bar shows.
  - Under the cursor: the name, plus the bar if the creature is hurt. A downed player always shows.
  - The crowd limit is unchanged.
- Looks:
  - A slug with its own Synty row keeps it.
  - Forge draws the slugs with no row, and the 8 slugs of `forge.forge_first`.
  - Of the 193 placeable slugs with a complete forge sync: 119 forge, 63 Synty, 11 primitive.
    Before this branch it was 146 / 36 / 11.

## What was built (commits on ws/hpbars)

- `e7ea9a9`: hit point bars.
  - `view/fx/nameplates.gd`: `fade`, `show_rule`, the HP-change tracking in `step`, the name-only
    plate, and a shadow under the short bar.
  - `view/fx/fx_view.gd`: DAMAGE and HEAL events call `plates.changed(dst)`. They used to "touch"
    both sides on every combat event, misses included.
  - `tests/test_plate_fade.gd`, 45 checks:
    - the fade curve
    - the rule
    - `arrange` with unnamed bars
    - `step()` on a real ClientWorld, with a camera in the test's scene tree
  - `tools/plate_sheet.gd`: a proof sheet of every plate form, each labelled with what
    `show_rule` decided.
- `2d3fcc6`: looks.
  - `view/actors/looks.gd`: `forge_rule`, and the header that documents the chain.
  - `data/looks.json`: the `forge` block (`person_types`, `forge_first`) and the `_comment`s.
  - `tests/test_looks.gd`: the new chain.
  - `tools/forge_sheet.gd`: a `forge=1` option that draws a Synty-first slug's forge body, for
    comparison with `no_forge=1`.
- Docs: plan.md "Decisions" and its art-sources row, architecture.md (Track G), m6.md,
  m6-integration.md, a "superseded" note in forge-art.md, and this report.

## API as built

### Nameplates (`view/fx/nameplates.gd`)

- `HOLD_S := 2.5` and `FADE_S := 1.5`: seconds at full strength, then seconds to fade.
- `static fade(t, hold := HOLD_S, out := FADE_S) -> float`:
  - 1 while `t <= hold`, so a negative `t` (clock order) also gives 1
  - then `1 - smoothstep` down to 0 at `hold + out`
  - 0 for `INF` (never changed)
- `static show_rule(hp, max_hp, since, hovered, player, downed, ranked) -> {alpha, bar, name}`,
  where `since` is the seconds since the last change (`INF` if none was seen). The first case that
  applies wins:

  | Case | alpha | bar | name |
  |---|---|---|---|
  | downed | 1 | yes | yes |
  | hovered | 1 | if hurt or changed lately | yes |
  | otherwise | `fade(since)` | yes, when alpha > 0 | for a player or a ranked foe |

- `changed(id)` starts the fade now. `step()` also notices a new `hp` in the snapshot, which covers
  regeneration and ticks that send no event.
- State: `changed_at` (id -> msec), `last_hp` (id -> hp). `forget(id)` drops both.
- Removed: `touch()`, `active`, `FIGHT_SECS`.
- `arrange(want, sc)`: a want entry may carry `named: false`. Such a bar goes straight to the
  compact rows (BAR_ROWS high), so the crowd limit still holds.
- Drawing:
  - the rank frame is drawn only around a bar
  - a name-only plate (hovered at full health) is the name in the rank's colour, with no frame
  - plate alpha is the Control's `modulate.a`

### Looks (`view/actors/looks.gd`, `data/looks.json`)

- The order, first available wins:
  1. the slug's own row (Synty)
  2. the forge body
  3. by_type (Synty)
  4. a primitive
- Forge comes first:
  - for an SRD slug with no row of its own (one that would reach by_type, by_size or a
    primitive)
  - for `forge.forge_first`
- Forge is the fallback when a row's Synty files are missing.
- A player look, or a people look of a `forge.person_types` type, never takes a forge body. Neither
  does a slug in the quarantine. These rules are unchanged; `person_types` was named
  `synty_first_types`.
- `forge_rule(look, slug, ctype) -> [forge_allowed, synty_first]`, where
  `synty_first = own row and not forge_first`.
- `keep_synty` is gone, because it is now the default.

`forge_first` (8), judged on `rows_no_forge.png` against `rows_forge.png`: the 28 slugs that have
their own row and a synced forge body, drawn both ways.

| slug | reason |
|---|---|
| goat, giant-goat | the Synty goat lies on its side |
| polar-bear | the Synty bear stays brown under the white tint |
| werewolf | the Synty stand-in is a plain human hunter |
| warhorse-skeleton | a living horse with a bone tint |
| kobold-warrior | a tinted goblin; a kobold is a small reptile |
| gnoll-warrior | a human butcher; a gnoll is hyena-headed |
| treant | a small antlered person, far under a Huge tree's box (not placed today) |

Looked at and left Synty, because they read as the creature even if loosely:
- the wolves (dire and winter wolves are small in their boxes)
- mastiff (a tinted wolf)
- the bears other than polar
- boar and giant boar
- deer, elk, giant elk (a moose)
- the horses
- ghost, specter, wraith (tinted ghost knights)
- lich, troll, medusa, the golems, the goblins

The loose analogues that are not synced here were judged on forge-art's `compare_synty.png` and
left Synty: hobgoblins (goblin knight), bugbears (orc), ogre and the giants (the barbarian giant),
ghoul, ghast and mummy (tinted zombie), vampire-spawn, minotaur-skeleton, and flesh golem.

## Deviations

- Healing a creature to full still shows its full bar, which then fades. The ask was "full opacity
  right after damage or healing", so this reads as the intent. Outside that window, a full-health
  creature never shows a bar.
- Engaged (what the next swing lands on) no longer shows a plate by itself. The target outline
  already marks it, and showing a name for every engaged full-health foe would add the business
  the user asked to remove. Engaged still sorts first for room.
- A creature first seen already hurt shows no bar until its hit points change. It is "hurt but not
  recently damaged".
- `tools/plate_sheet.gd` and the `forge=1` option of `tools/forge_sheet.gd` are outside the listed
  files. Both are tools nobody else owns.

## Measured numbers

- Tests: `tools/test.sh looks plate_fade nameplates` passes with fetched art, and again with
  `assets/` moved away (179 checks in 4 files, no art).
  - test_plate_fade: 45 checks.
  - test_looks plus its neighbour: 127 checks.
  - look_below, peoples_below and swings, which build looks: 1073 checks, ALL PASS.
- Resolution of the 193 placeable slugs (the forge-art inventory list), probe
  `~/.cache/hpbars/probe/counts.gd`:

  | | forge | Synty (own row + by_type) | primitive |
  |---|---|---|---|
  | complete sync (all but the 18 slugs with no forge body, and the quarantine) | 119 | 63 (61 + 2) | 11 |
  | this machine today (266 synced, see open issues) | 107 | 71 (62 + 9) | 15 |
  | forge-art, before this branch (complete sync) | 146 | 36 | 11 |

  - The 61 own-row Synty slugs are the 67 rows the inventory found, minus the 6 placeable
    `forge_first` slugs (polar-bear and treant are not placed). They include the 18 human NPC
    blocks.
  - By_type: lamia and xorn (no forge body).
  - Primitive: behir, constrictor-snake (quarantined), drider, flying-snake,
    giant-constrictor-snake, giant-venomous-snake, grick, purple-worm, scorpion,
    swarm-of-venomous-snakes, venomous-snake.
- UI tour fight (CPU Vulkan, so only relative): fx 442 µs a frame on average before and 499 µs
  after. These were different fights with different events, so the difference is noise.
- Gate: see Verification.

## Pictures (all looked at)

- `before/05_fight_telegraph.png`, `before/06_fight_numbers.png`: the old rule.
  - Every goblin carries a name and a bar, including the champion, the elite and one nobody had
    hit.
  - Three full-width plates stack over the pack.
- `after/05`, `after/06`, `after/07_after_fight.png`: the new rule (a fresh world, same seed).
  - Only the critted goblin has a bar: a short red one with no name.
  - The champion and elite were missed in this run, so they show nothing.
  - After the fight there is no plate at all.
- `plates.png` (`tools/plate_sheet.gd`, over the old after-fight frame): every form at scale 1.5.
  - a hit goblin, full and at half fade
  - a hurt goblin hit long ago, and a full-health goblin in a fight (both nothing)
  - a hovered goblin (name only)
  - a minion; elite, champion and boss with their frames and affixes
  - a hovered boss at full health (name only)
  - a hurt player, and a downed player
- `crop_after06.png`: the wind-up `!` telegraph sits on the short bar at the head. The old full
  plate's bar sat at the same height, so this overlap is not new.
- `rows_no_forge.png`, `rows_forge.png`: the forge_first evidence (above).
- `proof_chain.png`, 32 slugs through the default chain:
  - Own rows draw Synty: goblin, hobgoblin, ogre, wolves, bears, skeleton, zombie, ghoul, troll,
    medusa, stone golem.
  - `forge_first` slugs and row-less slugs draw forge: polar bear, goats, werewolf, warhorse
    skeleton, kobold, owlbear, spider, darkmantle, dragon, cube, and others.
  - shadow (by_type skeleton) and ape (primitive) only wait for the re-sync.

## Open issues

- The forge is mid-change upstream. This machine's sync (`tools/bootstrap.sh`, 28.8 s, 2.5 GB)
  added 266 monsters and skipped 77 with "no idle clip", plus 3 with "no anims yet".
  - The 77 are the UAL bipeds forge-art saw in progress: ape, shadow, gnoll, hobgoblins, ogres,
    giants and others.
  - Hence the "today" row above. Re-sync when the forge settles; nothing in the chain needs to
    change.
  - gnoll-warrior's forge_first entry rests on forge-art's sheets, because it is not synced here.
- The `!` wind-up telegraph overlaps a short bar at the head (see Pictures). It did before too.
  Lifting the bar by the telegraph's height while a wind-up shows is the obvious fix (small).
- The fade timer uses `Time.get_ticks_msec()` (wall time). Engine.time_scale (the combat tour's
  slow motion) does not slow it.
- Feel is unplayed. HOLD_S and FADE_S are constants in nameplates.gd. Move them to
  `data/combat.json "feel"` if the user wants to tune them.

## Verification

`tools/gate.sh` at `2d3fcc6` (all the code; only docs came after), with Synty, 266 forge monsters
and the props fetched:

- import: exit 0
- suite: 10737 checks in 84 files, 155 s, ALL PASS
- net smokes: all 8 PASS
- unseeded end-to-end runs: all 3 passed, 264 checks each, ALL PASS

No pace change in this track, so the extra E2E list was not needed. `git status` shows no art: `assets/`
stays git-ignored.
