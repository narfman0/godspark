# Track: Rules (M2 wave 1)

Leveling to 100, experience, SRD choices, Knacks and deeds, rests, downed and death, as the
`HostSystem.RULES` system pair. Design: [m2.md](../m2.md); contract:
[architecture.md](../architecture.md), "M2 contracts".

## What was built

| File | What |
|---|---|
| `core/rules/rules_system.gd` | `RulesSystem` (host): XP, levels and rewards, choices, Knacks, deeds, rests, downed/death/respawn, the CHAR mirror, save hooks |
| `core/rules/rules_client.gd` | `RulesClient` (client): mirrored sheet and downed states, signals and request methods for the interface |
| `core/rules/rules_codec.gd` | `RulesCodec`: message kinds, enums (`Down`, `RestEv`, `Resting`, `Debug`) and byte layouts |
| `core/rules/knacks.gd` | `Knacks`: the knack table, deed counters, deterministic deed-weighted offers |
| `data/rules/knacks.json` | 67 knacks: 18 skills, 11 tools, 15 languages, 14 people Bonds (every culture in `data/sim/cultures.json`), 9 beast Bonds; deed weights and units |
| `core/rules/level_track.gd` | `XP_SCALE` = 15 (was 1.0) |
| `tools/xp_pacing.gd` | minutes per level 1..100 under an assumed kill-rate table; best-fit scale |
| `net/bot_client.gd` | additive: the `rules=1` scenario (read from the command line by the bot itself) |
| `tools/net_smoke.sh` | additive: `RULES=1` variant, `HOST_EXTRA` / `BOT1_EXTRA` / `BOT2_EXTRA` passthrough |
| `tests/test_rules_codec.gd`, `test_rules_levels.gd`, `test_rules_rest.gd`, `test_rules_net.gd` | 307 checks |

## The client surface (for the interface track)

`var rules: RulesClient = cw.system(HostSystem.RULES)` (installed by `Systems` on welcome).

Signals:

| Signal | When |
|---|---|
| `sheet_changed(sheet: Dictionary)` | join, and whenever anything but current HP changes (keys below) |
| `leveled(level: int, reward: int)` | once per level gained; `reward` is `LevelTrack.Reward` |
| `choice_pending(choice: Dictionary)` | a choice opened: `{key, kind, label, count, options: [{id, name, level?, modelled}]}` |
| `downed_changed(id, state, successes, failures)` | any player near you (or you) went down, got up, stabilised, died; `state` is `RulesCodec.Down` |
| `rest_event(ev: Dictionary)` | `{event: RulesCodec.RestEv, healed, dice, reason, names}` |
| `xp_gained(amount: int, source: String)` | every XP award |
| `notice(text: String)` | a refused request ("answer refused: pick 2"), "bob got you up" |

State: `sheet`, `choices` (key -> choice, only open ones), `downed` (id -> {state,
successes, failures}, only those not UP), `last_rest`, `notices`; `level()`,
`is_downed(id := mine)`, `state_of(id)`, `pending_keys()`.

Requests (each validated on the host; a refusal comes back as `notice` or a `*_STOP` rest event):

| Method | Notes |
|---|---|
| `answer(choice_id, answer: Array)` | key as in `pending`: `"<class level>:<id>"` (SRD), `"knack:<level>"`, `"boon"`, `"3:subclass"`. `kind == "asi"`: `[feat, details...]` (`["ability-score-improvement", "str", "con"]`, `["grappler", "dex"]`, `["skilled", s1, s2, s3]`, `["alert"]`); other kinds: exactly `count` distinct option ids |
| `pick_knack(id)` | from the oldest open offer holding it |
| `rest_short()`, `rest_long()`, `stand()` | `stand` cancels either rest |
| `revive(target_id)` / `revive_stop()` | hold: the host counts while you stay in reach |
| `respawn()` | only when dead |
| `debug(op: RulesCodec.Debug, n)` | XP n, LEVEL target, AUTO, HURT n, DIE, HEAL n; host needs `cheats` |

Option text is not on the wire: look it up in the client's own `SRDContent` (spells, feats,
subclasses) or `Knacks.def(id)` (`name`, `text`).

The sheet: `level, xp, xp_level` (threshold of this level)`, xp_next, class, subclass,
species, background, class_level, scores` (6, after gear)`, hp, max_hp, hit_dice,
hit_dice_max, slots` ([left, max] x 9)`, uses` ({resource: [left, max]})`, spark_slots,
knacks` ([id])`, bonds` ({key: strength})`, boon, pending` ([{key, kind, label, count}])`,
state` (Down)`, successes, failures, resting` (Resting)`, rest_ready` (a long rest is allowed
by the once-a-day rule)`, bed` (Vector2i or null). Live hit points: use `cw.hp` / VITALS; the
sheet's `hp` is as of its last send.

## Messages (system 1; layouts in `rules_codec.gd`)

| Kind | Dir | Payload |
|---|---|---|
| 1 CHAR | to owner | full sheet, about 230-270 B at level 24 |
| 2 CHOICE | to owner | one pending choice with options (ids and names only; a wizard's spell list about 2.6 KB) |
| 3 LEVEL | to owner | u8 level, u8 reward |
| 4 DOWNED | near + owner; to a joiner for each down player | u32 id, u8 state, u8 successes, u8 failures |
| 5 REST | to owner | u8 event, u16 healed, u8 dice, str reason, names |
| 6 GAIN | to owner | u32 xp, str source |
| 7 NOTE | to owner | str |
| 64 ANSWER / 65 KNACK / 66 REST_SHORT / 67 REST_LONG / 68 STAND / 69 REVIVE / 70 RESPAWN / 71 DEBUG | to host | see the codec |

CHAR is sent on join, after every change (marked dirty), and checked every 15 ticks with
the current HP masked out, so combat damage alone never resends it. CHOICE goes once per
newly opened key, before the CHAR that lists it. Smoke run (rules variant): 52 SYS messages,
963 bytes in total.

## Rules and numbers chosen

**Experience.** `on_kill`: stat block XP (meta `xp` replaces it) times the rank multiplier:
meta `xp_mult`, else `RANK_XP[meta "rank"]` = minion 0.25, standard 1, elite 2, champion 4,
boss 6. In full to every player not dead within 24 tiles (body centres) of the victim, and
to the killers wherever they are. Deeds `kill`, `kill:<SRD type>`, `beast:<kind>`.
`XP_SCALE` = 15 (pacing below).

**Levels.** Each threshold crossed calls `Character.gain_level()` and applies the reward:
SPARK_SLOT nothing (the sheet's `spark_slots` follows the level; Items owns sparks); VIGOR
nothing (in LevelTrack); KNACK opens an offer of three; CLASS_LEVEL opens the SRD's choices
(`Character.pending_choices`); EPIC_BOON (100) opens a pick of the 7 SRD Epic Boons
(recorded, not applied: the addon has no boon effects). Unanswered choices are simply not in
the build (an ASI not taken raises nothing; spells not picked are not known). SRD 5.2.1 has
one subclass per class, so it is taken at class level 3 without asking; a `"3:subclass"`
choice appears only if a class has more than one. A player leveling while downed stays at 0
HP.

**refresh(e).** HP and Hit Point Dice captured from the old combatant, then
`Character.make_combatant`, Knack skills set proficient, `ItemEffects.apply(c,
items.gear_mods(e))` when Items exists, max HP re-derived from `LevelTrack.max_hp` with CON
after gear, spent slots and uses carried over (new maxima add their gain), death saves,
conditions, effects and temp HP carried over by reference, `e.stats = ch.move_stats(c)` then
`items.apply_sparks(e, stats, out)` (`out` kept as `rules.extras(e)`), resync.

**Knacks.** Offered at each KNACK level: three, weighted by the deeds of the band (growth
since the last offer), sampled without replacement with an RNG seeded from name, level and
world seed (never `Dice`). Never one held or already on offer; never a skill already
proficient. Weight = 1 + sum(w * min(4, delta / unit)), units per counter prefix in the JSON.
Effects: skill -> proficiency on the combatant; tool and language -> recorded
(`proficiencies(id)`), the addon has neither; Bond -> strength 1 (`bond(id, key)`), nothing
reads it yet.

**Deeds** (`Character.deeds`, ints; `a:b` also adds to `a`): `dig[:tile]`, `place[:tile]`
(from the host's EDIT_RESULT events and `world.tile_changed`), `run`, `climb`, `fall`,
`swim` (tiles, from accepted body movement and flags), `underground[:band]` (seconds below
surface - 2; bands from `meta.bands`: caves, deeps, nadir, `shallows` for the surface band,
`caves` on worlds without bands), `sleep`, `rest`, `kill[:type]`, `beast:<kind>`, `revive`,
`downed`. Fed later by others through `add_deed`: `trade[:culture]`, `craft[:what]`,
`kindle`.

**Short rest.** Request; needs a campfire tile within 3 tiles of the body's cells, no living
monster (without meta `friendly`) within 12 tiles, not `combat.in_combat(e)`, not down. 5 s
standing: interrupted by any HP loss, moving 0.6 tiles, the campfire going, a monster coming
near or combat. Then spends `min(left, ceil(missing / (die/2 + 0.5 + CON)))` Hit Point Dice
through `SRDRest.short_rest_combatant` (short-rest features too).

**Long rest.** Request; a bed tile within 2 tiles, not down, and nothing hostile near. There is no
once-a-day limit (the user dropped the SRD's 24 hours; `LONG_REST_EVERY_HOURS` is 0). The player stays in bed until they move 2
tiles, the bed goes, or they are hurt. While some living (not dead) player is up, those in
bed get BED_WAIT with the names still up. When all are in bed (or one alone): the clock
jumps to the next 06:00 through `WorldHost.sleep` (the sim catches up under its per-tick
budget), each sleeper gets `SRDRest.long_rest_combatant` plus all Hit Point Dice (the
addon's restores only class-level many), that bed becomes `Character.bed`, deed `sleep`.

**Downed.** At 0 HP (`player_dropped`, or seen in the tick when something set HP to 0):
Unconscious, frozen. The host holds the body: if its client moves it more than 0.3 tiles
sideways or upward, the host teleports it back (CORRECT with a bumped epoch); falling is
allowed. The client freezes itself too (`cw.stats` swapped for a still copy). Digs are
stopped. A death save every 4 s with `DeathSaveTracker.roll` (host dice): 3 successes ->
STABLE, up at 1 HP after 3 s; natural 20 -> up at 1 HP; 3 failures -> dead.
`player_dropped` on a downed player = damage while down: one failure (two with `crit`), and
a stable player starts saving again. Revive: an ally (up) within 3 tiles (centres) holding
revive for 2 s -> up at 1 HP. Any healing: `rules.heal(e, n)` (the addon's `heal` does
nothing at 0 HP), or anything that writes HP above 0 is seen next tick. Dead: auto respawn
after 10 s or on `respawn()`, at the bed if its tile is still a bed, else the nearest shrine
within 96 tiles of where they died, else the world spawn; long-rested (HP, all dice, slots,
uses); nothing lost. Solo and co-op are the same rules.

**Persistence.** Knacks, deeds, bed: in the Character record. `save_player`: open Knack
offers, boon (open/taken), bonds, the deed mark, `rest_at`, downed state with successes and
failures, slots and uses spent. JSON floats are made ints on load (`Character._ints` for
deeds and the mark).

## XP pacing

`tools/xp_pacing.gd` (assumed numbers, labelled in the file): the band a player of a level
mostly fights in, kills per minute there, the SRD XP of typical monsters, rank mix:

| Band | From level | Kills/min | Typical monsters (SRD XP avg) | XP/kill with rank mix | XP/min |
|---|---|---|---|---|---|
| surface | 1 | 10 | goblin minion/warrior, wolf, giant rat, bandit (35) | 24 | 236 |
| shallow caves | 10 | 6 | skeleton, zombie, giant spider, gnoll, dire wolf, bugbear (133) | 112 | 672 |
| caves | 25 | 4.5 | ghoul, ogre, grick, mouther, gargoyle, owlbear, basilisk (486) | 408 | 1836 |
| deeps | 45 | 2.3 | chuul, roper, otyugh, drider, wraith, xorn, troll (1771) | 1196 | 2750 |
| nadir | 75 | 0.75 | cloaker, aboleth, fire giant, behir, stone giant (4980) | 3361 | 2521 |

Best single scale (log error against: levels 2-5 4.5 min, level 50 20, the 90s 60, 40 h):
15.1; set **15**. At 15: levels 2-5 take 2.9-4.8 min, levels 11-15 about 7, level 50 23.2,
the 90s 58.3 on average, level 100 59.5; level 10 at 0.5 h, 25 at 3.1 h, 50 at 10.4 h,
75 at 21 h, 100 at 41.8 h. The curve's shape comes from the assumed table (the SRD's XP
thresholds track its monster XP, so without fewer kills per minute deeper the minutes per
level would stay flat); re-run with measured rates when the spawn director exists.

## Measured

| What | Measured |
|---|---|
| Rules tick, 2 players, nothing happening | about 16 us per host tick in all |
| `award_xp` 1 -> 24 | 1.2-1.5 ms |
| `auto_answer` at 24 | 1.9 ms fighter, 5 ms wizard |
| `refresh` | 0.2-0.25 ms |
| `pending` recompute (after a change) | up to 3 ms (wizard, spell lists); cached otherwise |
| Smoke host tick, rules variant | avg 218 us, max 11 ms (the debug level-24 jump with auto answers) |
| Tests | 2009 checks (1702 before) |

## Deviations from the contract, and hooks outside my files

- `player_dropped(e, crit := false)`: the optional `crit` (SRD: a critical hit on a downed
  creature is two failures). Combat should call it for every hit on a player at 0 HP.
- Added calls: `heal(e, amount)` (Combat and Items must use it for healing, or a downed
  player stays down until the next tick sees HP > 0), `is_dead`, `bond`, `proficiencies`,
  `extras`, `award_xp(..., source)` returns levels gained, `sheet`, `pending`, `answer`,
  `pick_knack`, `auto_answer`, `teleport`, `respawn_point`.
- Rank multiplier is read from Object meta on the HostEntity (`rank`, `xp_mult`, `xp`);
  `friendly` meta exempts a monster from blocking rests. The Monsters track should set these.
- **Teleport and holding a downed body** append a `WorldHost.Ev.CORRECT` to `host.outbox`
  and bump `e.epoch` from the rules system (the same event `submit_state` makes, `why` = OK);
  no edit to `world_host.gd`. A `WorldHost.teleport(e, pos)` would be cleaner later.
- **Deeds for digs and places** are read by scanning `host.outbox` for EDIT_RESULT during the
  rules tick and connecting to `world.tile_changed` for the old tile. A CHECK_REQ drains the
  outbox before the tick, so a dig in that tick can be missed (rare).
- **Cheats**: `RulesSystem` reads `cheats` from `OS.get_cmdline_user_args()` itself (main.gd
  untouched); tests set `rules.cheats`.
- **Bot**: reads `rules`, `rules_level`, `rules_role` from the command line itself (main.gd
  untouched). **net_smoke.sh**: `RULES=1` and the `*_EXTRA` passthrough variables.
- No `Presenter` method added.
- Species and background are stored but not applied (the addon's `make_character` takes
  neither).

## Open issues

- A downed player can still place tiles (WorldHost has no "can act" hook for edits); digs are
  stopped each tick.
- Gear CON above the build's: `Character.capture` (used by `WorldHost._store_record`) clamps
  HP to `Character.max_hp()` without gear, so a player saved above that max loses the excess.
- Epic Boons and tool/language Knacks are recorded only; Bonds have no readers yet.
- The CHAR sheet's `hp` is not live (VITALS is).
- The respawn shrine search scans up to 193 x 193 cells once per respawn without a bed.
- Not tested with the Combat or Items systems present (their calls are guarded and
  exercised only by `has_method` checks).

## After the integration pass

The seams this track left open were wired in [m2-integration.md](m2-integration.md); the public
surface it added here is listed in architecture.md, "M2 contracts / Integration".
