# Track: Combat (M2 wave 1)

Branch `ws/combat`. Real-time d20 combat at an ARPG pace: a hit must physically connect on
the host, then the addon rolls. Contract: [architecture.md](../architecture.md), "M2 contracts
/ Combat"; design: [m2.md](../m2.md), "Combat feel".

## What was built

| File | What |
|---|---|
| `core/combat/combat_system.gd` | `CombatSystem` (HostSystem.COMBAT): per-entity state, the swing/cast state machine, contacts, projectiles, spells, round clocks, durations, fall damage, conditions to movement, death and downed flow, events, STATUS / SPELLS |
| `core/combat/combat_client.gd` | `CombatClient`: intents, events, status, spells, event log, own movement limits, a scripted `fight_step` for bots |
| `core/combat/combat_codec.gd` | `CombatCodec`: every SYS layout (header of the file), `describe(ev)` |
| `core/combat/combat_tempo.gd` | `CombatTempo`: weapon tempo classes, combo timelines, cast tempo, duration table, reach and range |
| `core/combat/hit_shapes.gd` | `HitShapes`: box gap, melee arc, segment vs box, SRD areas, line of effect, cover, ballistic aim |
| `core/combat/combat_sight.gd` | `CombatSight`: host light (lazy LightEngine + player torches), senses, `can_see` |
| `core/combat/monster_moves.gd` | `MonsterMoves`: every attack action as a WeaponData, save actions, Multiattack parsed |
| `core/combat/combat_brain.gd` | `CombatBrain`: the one reference brain |
| `data/combat.json` | every tunable |
| `tools/arena.gd` | headless scripted fights and the support reports |
| `tests/test_combat.gd`, `tests/test_combat_net.gd` | 210 checks |
| outside `core/combat` (additive) | see "Hooks outside the track" |

## Tempo (data/combat.json)

An Attack action is wind-up, contact frame(s), recovery. The weapon picks the class from its
SRD properties (the pack row: the addon's bitmask has no Heavy).

| Class | Weapons | Wind-up | Recovery | Action | Sweep |
|---|---|---|---|---|---|
| light | dagger, shortsword, scimitar, sickle, club, handaxe | 0.15 | 0.35 | 0.50 s (2/s) | 0 |
| plain | one-handed: longsword with shield, mace, rapier, flail | 0.20 | 0.40 | 0.60 s | 1 |
| versatile_two | versatile with no shield (longsword, quarterstaff, spear) | 0.22 | 0.46 | 0.68 s | 1 |
| heavy | Heavy or Two-Handed melee (greatsword, greataxe, maul, glaive) | 0.26 | 0.49 | 0.75 s | 2 |
| thrown | a thrown weapon, darts | 0.18 | 0.42 | 0.60 s | - |
| bow | shortbow, sling | 0.22 | 0.43 | 0.65 s | - |
| heavy_bow | longbow | 0.26 | 0.49 | 0.75 s | - |
| loading | crossbows, firearms, blowgun | 0.22 | 0.78 | 1.00 s | - |
| unarmed | no weapon | 0.12 | 0.33 | 0.45 s | 0 |
| monster | stat-block attacks | 0.50 | 0.60 | 1.10 s | 1 |
| cast: action | Action spells (any class) | 0.28 | 0.32 | 0.60 s | - |
| cast: bonus action | Healing Word... | 0.15 | 0.15 | 0.30 s + 2 s bonus timer | - |
| cast: reaction | Shield | 0 | 0 | instant, 2 s reaction timer | - |

Why:
- **Light swings twice a second** (the brief), and is the fastest: it also stands in for the
  Light property's off-hand attack, which is not modelled.
- **Heavy hits harder per swing and slightly higher DPS.** With a +3 modifier: dagger 11/s,
  scimitar 13/s, longsword one-handed 12.5/s, greatsword 13.3/s, greataxe 12.7/s. Heavy
  weapons cost the off-hand and a shield in the SRD, so they keep a small edge; the gap is
  much smaller than the SRD's per-attack gap (10 vs 5.5) because light weapons swing faster.
  Masteries and Fighting Styles stay SRD (Graze, Vex, Great Weapon Fighting widen it: see the
  arena).
- **An action is an action.** A spell with casting time Action takes the plain weapon's 0.6 s,
  so a Fire Bolt and a longsword compare as they do in the SRD (both one action).
- **Extra Attack and Multiattack are combos inside the same action time**: contacts at
  wind-up, then `gap` apart (at most 0.22 s), taken out of the recovery (at least 0.08 s
  left). n swings cost what one costs, so damage scales with n exactly as in the SRD while the
  pace stays the weapon's. Level 25 fighter (class 6): two hits 0.22 s apart every 0.6 s.
- **Monsters wind up 0.5 s** (Wayfarer's readable telegraph; breath weapons 0.8 s) and act
  every 1.1 s, so players get about 1.8x the monsters' actions per round. That is the
  ARPG's power fantasy; `weapon_tempo.monster` is the knob.
- **Bonus action and reaction** each have their own 2 s timer (`timers`). A bonus-action cast
  still plays a 0.3 s sequence (it blocks starting an attack for that long).
- **Movement during wind-up and recovery is allowed at full speed** for players
  (`move_mult_during_swing` = 1.0, unused: movement feel is untouched). The reference brain
  stands still through its wind-up and recovery, which is what makes it readable.
- **Rounds.** Each combatant has its own round clock (`K.ROUND_SECONDS` = 2 s) started the first
  time it acts or is acted on. Every boundary runs `SRDEffects.turn_ended` then `turn_started`
  (expiry, repeat saves, once-per-turn: Sneak Attack, Cleave, riders), and monster recharges
  (`MonsterSpells.recharge`, `MonsterActions.start_turn`).
- **Durations** come from the table: `1 round` 2 s, `1 minute` 20 s, `10 minutes` 120 s,
  `1 hour` 300 s, `8 hours` 600 s, `24 hours` 1200 s (otherwise n x per unit, capped at a game
  day). A cast's timed effects stop counting turns and end on a timer; Concentration ends with
  it. Instantaneous spells keep the addon's turn-based riders (Ray of Frost, Sap...).

## Hit rules (all on the host)

- **Melee arc**: reach `K.ft(5)` = 2 tiles (Reach: 4; monsters: their stat block's reach),
  measured box to box like SRD squares, inside +-70 deg of the aim from the attacker's
  centre, with a line from the centre to the target's box. Overlapping boxes count unless the
  target is behind. A swing that touches nobody rolls nothing (`counts.whiffs`).
- **Targets per swing**: the nearest touched creature takes the full SRD attack
  (`AttackResolver.weapon_attack`). Up to `sweep` more touched creatures (light 0, plain and
  versatile 1, heavy 2, monsters 1) take a **sweep**: an attack roll with the same bonus (no
  crit doubling, no riders, no Sneak Attack) that deals half the weapon's dice and no ability
  modifier. **Cleave** keeps its meaning: once per round, the first touched creature within
  5 ft of the primary target instead takes a real Cleave attack (`opts.cleave`: full dice).
  Single-target damage, and so every build-to-build ratio, is untouched by sweeps.
- **Projectiles** (arrows, bolts, thrown weapons, spell bolts, Magic Missile darts) are a list
  on the host, stepped in sub-steps of at most 0.5 tile per tick: they fly with gravity per
  kind (`projectiles`), are lobbed to pass through the aim point, stop on the first solid tile
  and hit the first hostile body on the segment (allies are passed through). The roll happens
  at impact. Long range (past normal range) gives Disadvantage; the max distance is the long
  range.
- **Areas**: sphere and cylinder (a circle in side view), cone (as wide as it is far), line
  (2 tiles wide), cube (one face on the origin). Self-origin shapes start at the caster and
  skip it; others at the aim point clamped to range and stopped by the first wall. A creature
  is in it if the shape overlaps its box and a line of effect from the origin reaches one of
  its 3x3 sample points. Friendly fire is the SRD's (Fireball hits allies in the sphere).
- **Cover**: rays from the attacker's centre (or the area's origin) to 3x3 samples on the
  target box: 3 of 9 blocked = half (+2), 6 = three-quarters (+5), 9 = total (nothing rolls).
  Creatures do not give cover.
- **Positional facts in opts**: `within_5ft` (box gap <= 2 tiles: Prone, auto-crits on
  Paralyzed/Unconscious), `cover` (per target name for spells), `ally_adjacent` (Sneak
  Attack), Disadvantage for ranged attacks with a hostile, active creature within 5 ft and for
  long range, and from sight: an unseen target gives Disadvantage, an unseen attacker
  Advantage.
- **Sight** (`CombatSight`): line of sight to a sample of the box, then light. The host has no
  LightEngine of its own, so one is built lazily over the host world on the first question
  (sun from the world clock). Every player is assumed to carry a torch (bright 8 tiles, dim
  16, line of sight), checked first and analytically, so the engine is only asked where no
  torch reaches. Darkvision: the stat block's senses for monsters, a species table for
  players (no species is applied to players yet: humans have none); Blindsight and Truesight
  see within range.
- **Aim and client-owned movement**: the host uses its latest accepted copy of a player's
  body. Measured at 50 ms one way, running at 13 tiles/s: the copy trails the player by
  0.9-1.1 tiles at the contact frame, against a 2-tile reach. Each intent carries the client's
  host-clock estimate; the host reads the one-way delay from it (half the trip, corrected for
  the clock's 25 ms bias, plus half a tick) and leads the player's box by velocity x delay
  when it tests shapes: error 0.87 -> 0.05 tiles in the test. Monsters are not rewound: a
  player sees them 100 ms + one way in the past.

## Brain API (host thread)

```gdscript
combat.can_act(e) -> bool                # alive, not downed, not Incapacitated
combat.busy(e) -> bool                   # mid-sequence or on the action timer
combat.start_attack(e, action := -1, aim := Vector2.INF, throw := false) -> bool
    # action: index into combat.actions_of(e); -1 = Multiattack, else the default attack
combat.targets_in_reach(e, action := -1) -> Array[HostEntity]   # facing ignored, sight line needed
combat.nearest_foe(e, max_tiles) -> HostEntity                  # visible hostile
combat.actions_of(e) -> Array            # MonsterMoves: {name, kind: melee|ranged|save, weapon?, riders?, save?, reach_ft, range_ft}
combat.filter_input(e, inp) -> PlayerInput   # brains MUST pass their input through this
```

`CombatBrain` (reference): walk straight at the nearest visible player (jump when blocked),
use a ready breath weapon if the target is inside it, else attack when `targets_in_reach`,
stand through wind-up and recovery, back off 0.6 s, repeat. Brainless monsters are stepped by
the combat tick with an empty input, so they fall, land (and take fall damage) and can be
shoved; a dead monster's brain is set to null so its corpse falls too.

## Conditions in real time

`STATUS.move_mult`, `no_jump` and `fear_src` (players) and `filter_input` (brains, brainless
monsters) change the input, never the controller:

| Condition | Effect |
|---|---|
| Grappled, Restrained, Paralyzed, Petrified, Unconscious | speed 0 (move_x 0, no climbing), no jump |
| Prone | crawl at half speed, no jump; stands by itself after 1 s if it can act |
| Speed penalties (Ray of Frost, Slow mastery) | move_x scaled by speed / base speed |
| Frightened | cannot step toward the source (from the effect's source) |
| Stunned, Incapacitated (and the above that imply it) | no actions (`can_act` false; a running sequence is cancelled) |
| Blinded, Invisible, Poisoned... | through the addon's roll modes and `CombatSight` |

All lists are data (`conditions`). Players' limits are enforced only by their own client (the
host's movement check does not know them).

## Damage, death and falls

- `combat.damage(src_id, dst, amount, dtype, opts)` goes through `Combatant.take_damage`
  (resistances, immunities, temporary hit points, Undead Fortitude), then Concentration
  (`damage_concentration_check`), then the 0 HP check.
- A monster at 0 HP: DEATH, its sequence and brain stop, it lingers 1.5 s, then
  `rules.on_kill(victim, killers)` and `items.on_kill(victim)` (each if present and it has the
  method), then `host.remove_entity`. Killers: every entity that dealt it damage, in order.
- A player at 0 HP: DOWNED, then `rules.player_dropped(e)` if Rules has it; `rules.is_downed`
  is honoured by `can_act` and targeting. Without Rules: after 3 s the player is back at the
  world spawn with full HP (through a CORRECT), a HEAL event announces it. Downed players are
  not targeted by attacks or areas.
- **Fall damage**: the net drop from the last footing (floor, ladder, water, wall, flight) to
  the landing, from the host's copy of the body (players: accepted states and their flags).
  1d6 per 10 ft once the drop is over 10 ft (a 5-tile ledge = 1d6; 50 ft = 5d6), at most 20d6;
  landing in water is free. A jump's own arc is not counted, so jumping on flat ground never
  hurts.

## Spells

`SpellResolver.cast` with targets from the shapes; slots spent at the contact frame (a
cancelled wind-up or a spell with nothing to target spends nothing); Concentration through a
`ConcentrationTracker` per entity. Players cast what their character has prepared
(`Character.resolved().spells`); SPELLS lists them with attack/save spells first.

| Shape | How targets are found | Verified end to end |
|---|---|---|
| area | the AoE from its origin | Burning Hands (cone), Thunderwave (cube + push), Fireball (sphere at a point) |
| bolt | one projectile per ray, spell attack at impact | Fire Bolt |
| darts | one projectile per dart at the picked target, auto-hit | Magic Missile (3 darts, 3 rolls) |
| foe | the hostile creature(s) nearest the aim within range and sight | Sacred Flame |
| ally | the caster or allies nearest the aim (touch: within 5 ft) | Cure Wounds, Healing Word (bonus), Bless (3) |
| self | the caster | Shield (reaction: instant, +5 AC before an incoming contact) |
| melee | the touch arc, first creature | (Shocking Grasp, not run in the tests) |

`tools/arena.gd report=spells` over the addon's 339 spells: **114 resolve through the shapes**
(36 area, 37 foe, 16 bolt, 13 ally, 7 melee, 4 self, 1 darts; 32 of them are tagged `partial`
in the addon: damage works, a rider does not). Refused with a reason: 217 with no mechanics in
the addon (utility spells, disabled ones), 5 casting times that are not combat casts
(contact-other-plane, dream, geas, symbol, tsunami), Hellish Rebuke (reaction trigger not
modelled: only self reactions), Misty Step (teleport would move a client-owned body),
Spiritual Weapon (summons need a host-side force). Shield is a manual reaction: pressed
during a telegraph it raises AC at once; there is no automatic "when hit" trigger (the
resolver decides hit and damage in one call; see Addon wishes).

## Monster actions

`tools/arena.gd report=monsters` over the 330 stat blocks: 421 attack actions and 122 save
actions (breaths, auras with a save) are supported; Multiattack is parsed for 171 of 177
(not: bugbear-stalker, dryad, hydra, mummy-lord, oni, warrior-veteran; they make their default
attack); 3 have no attack (shrieker-fungus, jackal, seahorse). Recharge and 1/Day uses go
through `MonsterSpells`. Not supported: 28 action kinds (39 uses) such as Slowing / Weakening
Breath (no damage dice), Invisibility, Shape-Shift, Swallow, Charm, Create Specter; also
monster Spellcasting, Bonus Actions and Reactions (Nimble Escape, Parry), Legendary Actions,
riders that need a game answer (grapple on hit, teleports).

## Messages (SYS, HostSystem.COMBAT)

Layouts are in `core/combat/combat_codec.gd`. Client to host: ATTACK (13 B), CAST
(14 B + slug), CANCEL (0 B). Host to client: EVENTS (`u32 tick, u8 n`, then 9 B + per kind:
SWING +14 + name, HIT/MISS/CRIT +4, DAMAGE +5, HEAL +4, CONDITION +2, PROJECTILE +25...) sent
with `send_sys_near`, one message per chunk of origin per tick, at most 120 events each;
STATUS (34 B + concentration slug) to the owner when its cooldowns, slots or limits change;
SPELLS to the owner on join and when the character changes. Round trips, truncations and
unknown kinds are tested.

## Client surface (for the Interface track)

```gdscript
var cc := cw.system(HostSystem.COMBAT) as CombatClient
signal event(ev)                 # every event in order; ev.t = host tick, kinds CombatCodec.Ev
signal cooldowns_changed(status) # {action, bonus, reaction (s left, counted down locally),
                                 #  move_mult, flags (CombatCodec.ST_*), fear_src, slots [[left, max] x 9], concentration}
signal spells_changed(spells)    # [{slug, name, level, flags}] flags: CombatCodec.SPELL_*
cc.attack(aim, throw := false) -> bool    # rate-limited locally (busy, pending)
cc.cast(slug, level, aim) -> bool; cc.cancel(); cc.can_attack()
cc.spell_slot(i) -> Dictionary   # default bindings: i-th supported spell (attack/save first)
cc.filter_input(inp); cc.events_log (last 64); cc.busy_s
Presenter.combat_event(ev)       # LogPresenter: one line; ViewPresenter: attack/hit/death one-shots
```

Inputs: `attack` on F (held repeats, aim = tile under the mouse), `cast_1..cast_4` on Q, E, R,
T. Throwing has no key yet (`throw` is in the intent and tested in the arena only).

## Arena (tools/arena.gd, 20 seeds each)

Sustained damage against a dummy (AC 15, never fights back), 30 s:

| Build | Weapon | Hero DPS | Swings/s | SRD DPR (per action) | DPS / DPR |
|---|---|---|---|---|---|
| fighter level 5 (class 2) | longsword + shield | 5.60 | 1.67 | 3.48 | 1.61 |
| fighter level 25 (class 6, Extra Attack) | longsword + shield | 19.92 | 1.67 | 11.95 | 1.67 |
| fighter level 1 | dagger | 4.64 | 2.00 | 2.38 | 1.95 |
| fighter level 1 | shortsword (Vex) | 7.78 | 2.00 | 2.92 | 2.66 |
| fighter level 1 | longsword (two-handed) | 5.69 | 1.43 | 4.03 | 1.41 |
| fighter level 1 | greatsword (Graze) | 7.61 | 1.30 | 4.85 | 1.57 |
| fighter level 1 | longbow, kiting | 3.36 | 1.33 | 2.70 | 1.24 |

- **Extra Attack**: level 25 vs level 5 is 3.56x in DPS against the SRD's 3.43x per round
  (Extra Attack, +1 proficiency, the ASI). The combo keeps SRD ratios.
- **Greatsword vs dagger**: 1.64x DPS (SRD per attack 2.04x). Tempo alone gives 1.2-1.3x;
  Graze and the fighter's style add the rest. Vex (shortsword) is strong at 2 swings a second:
  its Advantage lands every other swing. Watch it by hand.
- Kiting with a longbow loses to melee (moving, lobbed shots at 10-20 tiles).

Fights (CombatBrain monsters):

| Build | vs | Win | Time to kill | Hero DPS | Taken DPS |
|---|---|---|---|---|---|
| fighter 1 | goblin-warrior x3 | 50% | 5.2 s | 6.5 | 2.7 |
| fighter 5 | goblin-warrior x6 | 50% | 11.1 s | 6.8 | 2.9 |
| fighter 25 | goblin-warrior x6 | 100% | 4.1 s | 20.5 | 3.3 |
| rogue 5 | goblin-warrior x3 | 30% | 4.2 s | 7.2 | 5.2 |
| fighter 5 | brown-bear | 100% | 3.7 s | 6.9 | 2.0 |

Three goblins for a level 1 fighter is a Deadly SRD encounter and plays like one (50%). Hordes
will come from minions (Monsters track); the monster tempo is the knob if packs of standard
monsters should be gentler.

## Numbers

| What | Measured |
|---|---|
| Tests | 1912 checks (1702 before; +168 test_combat, +42 test_combat_net) |
| Smoke (2 bots, 1 goblin) | NET SMOKE PASS; host tick avg 212 us, max 2.2 ms |
| Smoke FIGHT=1 SPAWN=goblin-warrior:2 | NET SMOKE PASS; bot1 killed 2 with 3 attacks (a sweep); tick avg 282 us, max 2.7 ms |
| Host light, first queries in a cold area | 5.6-5.8 ms once (one 4x4-chunk batch); a smoke run that queried it before the torch shortcut had a 21 ms tick |
| Aim error at 50 ms, running | 0.87 tiles at contact without lead, 0.05 with |
| SYS traffic | about 40 B per combat message |

## Hooks outside the track

All additive; nothing in `world_host.gd`, `protocol.gd` or the endpoints changed.

- `game/presenter.gd`: optional `combat_event(ev)`; `attach` connects the combat client's
  `event` signal when the system exists, `detach` disconnects it.
- `game/log_presenter.gd`: prints `combat <describe(ev)>`.
- `game/view_presenter.gd`: `combat_event` holds the existing one-shot states over the
  movement state ("attack" for the swing's length, "hit" 0.3 s, "death" until healed or
  removed), only for actors it has. Not looked at on screen (no art run).
- `game/local_input.gd`, `project.godot`: attack (F), cast_1..4 (Q, E, R, T); conditions
  filter the input.
- `game/main.gd`: bot option `fight=1`; host option `spawn_dx=N` (where `spawn=` places the
  first monster; the test world's wooden ledges start at the default -24, out of a bot's
  reach).
- `net/bot_client.gd`: a `fight` phase before walking (uses `CombatClient.fight_step`),
  prints `BOT <name> fight killed=N ...`.
- `tools/net_smoke.sh`: `FIGHT=1` variant (SPAWN_DX -44, checks the fight line).
- The host's CORRECT path is used from the combat system (outbox event with a new epoch) to
  move a player on the fallback respawn.
- `CombatClient` reads `ClientWorld._clock_synced` (via `get`) to know its clock is valid.

## Deviations from the contract

- No USE intent (items and class features like Second Wind or Action Surge are not wired).
- More event kinds: EFFECT, PROJECTILE, IMPACT, PUSH, CANCEL. `roll` is `d20` + `total_roll`
  + `ac`.
- Intents carry the client's clock instead of nothing: lag compensation.
- Monster combatant names get `#<entity id>` (the addon matches effects by name).

## Open issues

- **Needs hands on the controls**: the 0.5 s monster wind-up as a dodge window at real
  latency (what you see is 100 ms + one way old); light weapons' 2 swings/s with Vex;
  whether movement at full speed while swinging feels right or wants a small slowdown
  (`move_mult_during_swing` exists, unused); Shield as a manual reaction during telegraphs;
  the one-shot animation holds (never seen on screen); holding F to attack while the mouse
  aims; whether 3 goblins should be this dangerous at level 1.
- Players' movement limits are enforced by their own client only.
- Spell slots are spent on the Combatant; the Rules track should capture them into
  `Character.slots_left` (and rebuild without refilling).
- Not modelled: two-weapon fighting / Nick, opportunity attacks, grapple and shove, Action
  Surge and other features, monster spellcasting, bonus actions and reactions, legendary
  actions, creature cover, ammunition and thrown-weapon loss, Shield's automatic trigger.
- A player's Darkvision needs species traits (Character stores the label only).
- Downed players cannot be attacked (death-save failures from damage are the Rules track's
  call).
- `combat.damage` from a dead source still credits the kill; killers include monsters for
  monster-on-monster damage.

## Addon wishes (not changed here)

- A "would this hit" query or a pre-damage hook in `AttackResolver.weapon_attack` (a callable
  `on_hit_decided(attacker, target, ev) -> bool`) so reactions like Shield and Parry can fire
  between the roll and the damage.
- `WeaponData` with the Heavy property, and a `SRDContent.make_monster_attacks(slug)` that
  builds every attack action (with its riders) instead of only the first.
- A parsed `multiattack` list on the monster row.
- Effects keyed by a combatant id rather than its name.

## After the integration pass

The seams this track left open were wired in [m2-integration.md](m2-integration.md); the public
surface it added here is listed in architecture.md, "M2 contracts / Integration".
