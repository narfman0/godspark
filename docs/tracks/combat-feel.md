# Track: combat feel (M2 follow-up, from the first play)

Branch `ws/combat-feel`, cut from main 22308c9. The user played and said: "id like to add weapon
animations and swings and make combat great; i have no idea what i am hitting. make a 'dodge' type
key too where i roll or something." Movement is untouched: no tunable of `MoveStats` changed, and
terminal velocity stays 20.

## What was built

### 1. The dodge roll, on V

V was free, sits beside F (attack) under the same fingers, and needs no modifier. Shift is dash,
and Ctrl is taken for the hotbar wheel. It is in README's controls table and the in-game help.

- `core/combat/dodge.gd` steps the roll on the body from `PlayerController`; the same `Dodge`
  functions run on the client and the host.
- About two tiles over 0.4 s from a standstill, in the facing direction. Cooldown 1 s from the start
  of a roll. No resource.
- For the middle frames the hurt box is a tuck at the feet: 0.6 of the body's width, 0.32 of its
  height. Arrows pass over it. An area that reaches it still catches it.
- A melee arc spans 140 degrees and reaches the floor, so a tuck inside it would still be touched.
  The tuck escapes only if its top is under the line of the swing, which runs through the aimed
  height (`Dodge.under_blow`). A creature `too_big_tiles` tall or more (Huge and up) fills the
  space its blow comes through: nothing is under it.
- The host stores the roll from the press (`now - lead`), tests blows against `hurt_box`, keeps the
  cooldown, and refuses a roll from a slowed body or after a contact. A roll in a wind-up emits the
  existing CANCEL and the action is not spent. A blow that passes over emits WHIFF naming the
  roller, shown as "dodged".
- Bodies roll with `A_DodgeRoll_F_Sword`, a real tumble; a primitive spins instead.

### 2. Swings you can see

**Why swings had no animation.** The `attack` clip was `..A_ReturnToIdle_Sword`. Synty's combo
files are sections of one take: a ReturnToIdle file only holds the last pose for a second and
walks back, so there was no swing in it. Before `from_s`, the combo files only hold a pose too.

- `SwingPlan` (pure) turns a SWING event into clip segments on the swing's own clock: a move's
  `pre` span is stretched over the wind-up and its `post` over the rest of the action, so the
  contact falls on the data's `windup` at every tempo. The tempo numbers are unchanged.
- `SwingLayer` lays those clips over the movement, bone by bone, sampled from the tracks. Above
  the spine it always takes the swing; the legs keep running while the body moves and join in
  when it stands. Swinging does not slow the player (`tempo_move` stays 1.0) so this matters.
- The AnimationPlayers now run in manual mode, stepped by `ActorBody` so the layer comes after them.
- Clips retarget on first use, sampling only the span the moves use. Long Synty takes are mostly
  a hold, so this saves most of the work.
- Moves per class in `data/looks.json` `swings.tempo`:

| Class | Moves, in order | Clips |
|---|---|---|
| light | thrust, slash_a, slash_b | LightFencing, LightCombo |
| plain | slash_a, slash_b, slash_c | LightCombo A B C |
| versatile_two | heavy_b, stab, heavy_c | HeavyCombo, HeavyStab |
| heavy | heavy_b, heavy_c, heavy_a | HeavyCombo |
| thrown | throw | an emote: a baseball pitch |
| bow, heavy_bow, loading | shot | bow pack: draw, then loose |
| unarmed | punch | the sword pack's pommel strike |
| monster (Synty bodies) | heavy_b, slash_b, stab | as above |
| cast | cast | an emote: arms raised |

- **Contact times are chosen by eye.** The tip's fastest moment (`tools/clip_probe.gd`) is often the
  backswing: for `thrust` it said 0.567 s and the lunge is at 0.9 s. `tools/clip_sheet.gd` draws a
  contact sheet of the moves; the `moves` table came from that.
- Consecutive actions walk along the chain (reset after `combo_reset_s`). Extra Attack and
  Multiattack play a different move per contact, each sweeping the other way across the arc.
- **Weapons in the hand:** `data/looks.json` `weapons` maps 32 of the 38 SRD weapons to Synty meshes. A
  grip is a single number, written in the T-posed models' shared space, so it holds on both
  rigs. Bows sit in the left hand. Unmapped weapons (sling, dart, whip, blowgun, musket, pistol)
  and missing files are a plain bar. Drawn `thick` 1.6 times broader to read at game distance.
- Forge monsters carry their `wields` on `grip_r`.
- **The arc:** `Telegraphs` draws the shape the host tests, the attacker's box grown by the
  weapon's reach within `melee.arc_half_angle_deg` of the aim, and it follows the running body. A
  crescent (`SwingFx`, `slash.gdshader`) crosses that arc with its head at the middle on the contact.
- **Forge wind-ups:** `ForgeMonster.contact_of` finds the blow by forward kinematics and caches it.
  The attack clip is stretched so the blow lands on the wind-up, whatever its own timing.
- Bodies face their aim while they swing, even against the way they run (view only).

### 3. Knowing what you are hitting

- **Highlight:** `CombatClient.target_at(aim)` is the host's own choice: the same arc, reach, wall
  check and `HitShapes.nearer_touch` order. The creature gets a gold outline (`rim.gdshader`, an
  overlay, so skinned meshes follow); pale if under the aim but out of reach. Its plate shows even
  when plates are otherwise hidden. Life's calm townsfolk are left out until a fight names them.
- **The next swing's arc** stands faintly while a foe is near (`aim_arc_alpha`, `aim_arc_tiles`).
- **On contact:** a flash lights the victim in any light (`flash.gdshader`), the `hit` clip flinches
  it, and the attacker's client holds both bodies for `hit_stop_s`.
- **Hit:** white flash, an orange burst, the number, a crescent that turns orange.
- **Crit:** gold flash, a larger star and ring, a bigger gold number under "Crit!", a longer hold,
  a full-width gold crescent.
- **Miss:** no flash, no hold. A broken grey ring with a slash through it, "miss", a thin grey
  crescent. A swing that touched nothing shows the thin grey crescent alone.

### 4. Monster wind-ups

The telegraph is drawn in full from the first frame and fills over the wind-up. Its edge is
thicker and its base stronger than before; the monster's body burns vermilion, from
`windup_rim_min` to full at the blow. Tempo data is unchanged.

## API as built

- `CombatCodec`: Msg.ROLL, Ev.ROLL, Ev.WHIFF. SWING gains `gap`, `tempo`, `reach_ft`. STATUS gains
  `reach_ft`, `range_ft`. Protocol version 10.
- `CombatSystem.start_roll(e)`, `hurt_box(e)`. `CombatClient.can_roll(inp)`, `rolled()`,
  `target_at(aim)`. `ClientSystem.rolled()`. `PlayerInput.roll` (a trailing byte, so a plain step
  stays 2 bytes). `Body.roll_t`, `roll_dir`, `roll_speed`, `roll_cd`.
- `HitShapes.nearer_touch`: the host's order of a blow's touches, shared with the highlight.
- View: `SwingPlan`, `SwingLayer`, `SwingFx`, `HitStop`, `WeaponMesh`. `ActorBody.swing, roll, flinch,
  hold, set_weapon, set_rim, flash, stop_swing`. `AnimRetarget.load_clip` takes a `span`.
- `game/ui/combat_tour.gd`: `combat_tour=DIR` takes these pictures. `tools/clip_sheet.gd` draws the
  contact sheets.

## Tunables

`data/combat.json` `dodge`:

| Key | Default | |
|---|---|---|
| distance_tiles | 2.0 | from a standstill |
| duration_s | 0.4 | |
| cooldown_s | 1.0 | from the start of a roll |
| keep_run_speed | true | from a run it keeps the run's speed |
| hurt_from_s, hurt_to_s | 0.08, 0.32 | the tuck |
| hurt_width_mult, hurt_height_mult | 0.6, 0.32 | of the body's box |
| blow_clearance_tiles | 0.3 | tuck's top under the swing's line |
| too_big_tiles | 5.0 | a Huge body's height |
| host_slack_s | 0.12 | packets bunch up |

`data/combat.json` `feel` (view only):

| Key | Default |
|---|---|
| hit_stop_s, crit_stop_s | 0.06, 0.1 (0 disables) |
| flash_s, crit_flash_s | 0.12, 0.2 |
| flinch_s | 0.35 |
| fade_in_s, fade_out_s | 0.05, 0.12 |
| roll_fade_s | 0.03, 0.06 |
| combo_reset_s | 1.2 |
| moving_speed | 1.5 tiles a second |
| aim_arc_alpha, aim_arc_tiles | 0.32, 6.0 |
| slash_s, slash_lead_s | 0.14, 0.07 |
| slash_width | light 0.4, plain 0.5, versatile_two 0.6, heavy 0.75, unarmed 0.3, monster 0.6 |
| impact_tiles | hit 1.3, crit 2.2, miss 1.1 |
| impact_s | hit 0.22, crit 0.34, miss 0.3 |
| rim_m | 0.035 |
| windup_rim_from, windup_rim_min | 0.0, 0.35 |
| number_size | hit 24, crit 32, crit_label 30, miss 22, dodged 22 |
| crit_label_rise | 1.4 |
| colors | slash, slash_foe, hit, crit, miss, target, near, windup, flash, crit_flash |

`data/looks.json`: `swings` (clips, moves, tempo, upper_from), `weapons` (rows, grip, forge_grip,
primitive, thick).

## What was inherited and what changed

A previous agent left the roll uncommitted, with 7 tests failing.

Kept as it was: `dodge.gd`, the controller mode, the V key, ROLL and WHIFF, the codec, the wire
fields, `target_at`, `nearer_touch`, `clip_probe`.

Changed:

- The test suite: the failures were in the tests. The SWING round trip did not know the new fields;
  a goblin stood out of reach; the ledge was too far for two tiles; one check ran after the roll had
  ended. See below.
- The host now refuses a roll from a slowed body. Only the client did.
- `rolled()` no longer counts as an attack in `sent`.
- `clip_probe` reads the new table; its forge half moved to `ForgeMonster.contact_of`.

## Changes nobody asked for

- `attack` in `data/looks.json` `clips.actions` now names the real clip, not the ReturnToIdle.
- Fighting bots roll every 2.5 s, so the smokes cover rolls over real sockets. `BOT fight` prints
  `rolls=`.
- Telegraph arcs use the swing's real reach and box: a pike's was drawn at five feet.
- Slowed bodies cannot roll. This is the previous agent's rule and I kept it: a fixed-speed roll
  would escape a slow.
- `tests/data/asset_paths.txt` was refreshed from the asset server: 41 new paths, all on the server.

## Tests changed

- `test_combat_net`: the SWING row of the round trip now carries `gap`, `tempo`, `reach_ft`, and ROLL
  and WHIFF are added. The check is the same: every field comes back, no more and no fewer.
- No other existing test changed. `test_dodge` was new and uncommitted; four of its set-ups were
  wrong and are fixed, none weakened: the goblin one tile closer, to be in reach; the ledge one tile
  closer; "no swing from inside the roll" moved before the ticks that ended the roll.

## Verified

The suite and smokes results are below, from the rebased head.

