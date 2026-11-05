# Godspark

A co-op sidescrolling platformer set in a simulated world built on the SRD 5.2.1: a deep
Underdark, biomes with their own ecology, settlements that trade, raid and starve, and a
long road to godhood. Working title.

- Engine: Godot 4.7.1 (Forward+), GDScript.
- Status: M2, "Leveling and combat" (integrated, first time in players' hands): on top of
  M1's generated world, co-op digging and building, day and night and world history, there
  are now characters that level to 100, real-time d20 combat, monsters spawned around you,
  loot, gear and sparks. See [docs/m2.md](docs/m2.md), [docs/plan.md](docs/plan.md) and
  [docs/architecture.md](docs/architecture.md).

## What M2 added

- **Characters**: fighter, rogue, wizard or cleric (`class=` when you first join); levels 1-100
  where every fifth is an SRD class level and the levels between give spark slots, Vigor and
  Knacks (picked from what you did: deeds). XP from kills, shared with everyone nearby.
- **Combat**: real-time; every swing and spell is an SRD roll made on the host once the hit
  physically connects. Monsters wind up visibly before they strike. Downed at 0 HP: death
  saves every 4 s, a friend holds E to get you up (a healing spell or potion does too); dead,
  you wake at your bed or the nearest shrine with nothing lost.
- **Monsters**: SRD stat blocks with brains, ranks (minion, elite, champion, boss) and
  affixes, spawned off-screen around you by a director: small, minion-heavy packs by day near
  the settlement you start at, harder ones further out, at night and deeper down. Sim lairs
  become real creatures when you arrive.
- **Items**: an inventory and hotbar (what you dig is what you can place), a paper doll with
  ten rings, SRD magic items (attunement items bond at a campfire, no limit), ordinary gear
  with materials and affixes, loot on the ground.
- **Sparks**: found on elites and champions; kindle them at a shrine for movement and utility
  (run, jump, air jumps, dash, glide, dig speed and reach, light, swing speed ...). They never
  change attack rolls, AC, DCs or damage dice.
- **Rests**: hold E at a campfire for a short rest on Hit Point Dice; sleep in a bed for a long
  rest (the night passes when every living player is in bed).

```bash
git clone --recurse-submodules <this repo>
godot --headless --import
godot --headless -s res://tools/run_tests.gd     # prints ALL PASS
```

## Running it

```bash
tools/bootstrap.sh          # optional: fetch the art (about 57 MB, git-ignored); runs without it
godot                       # host a new dev world and play it (listen server on port 24650)
godot -- join=HOST[:PORT] name=ann          # join someone's game
godot -- offline gen=dev seed=7             # single-player, no network port
godot --headless -- dedicated port=24650 world=/path/to/world   # a server with no local player
```

Options (after `--`): `gen=dev|small|medium|large` and `seed=N` pick a new world;
`world=DIR` is where it is saved and loaded (default `user://worlds/dev`; a saved world there
is loaded instead of generating one); `gen=test` is the small flat test world; `name=X`;
`port=N`; `class=fighter|rogue|wizard|cleric` for a new character; `cheats` (debug keys and
DEBUG messages); `spawns=0|1` turns the spawn director off or on; `pack=goblin-warrior` (or
`SLUG:RANK`, `raiders:bandit`, comma-separated) spawns ranked packs near you; `xp=N`
multiplies kill XP; `sleep=HOURS` advances the world clock at start; `timeout=S`; `shot=PATH.png
shot_after=S` saves a screenshot and quits; `ui_tour=DIR` (with `offline cheats`, under
`tools/soft_godot.sh`) drives the interface through its screens and saves a picture of each. `game/main.gd` lists them all. The world, the
clock, the world history and the players are saved on exit.

## Controls

Terraria-like: the selected hotbar item decides what the left mouse button does. Hotbar slot 1 is the
attack slot: a new character starts with it selected and empty (it shows the wielded weapon,
which lives on the paper doll), so a left click fights; the kit's blocks, torches, campfire,
potions and bed are on slots 2-6, and loot never lands in slot 1. A hint above the hotbar
("Left click: use what is selected. F: always attack. Right click: dig.") fades after your
first attack.
**Digging moved from the left to the right mouse button.**

| Action | Keys |
|---|---|
| Move left / right | A / D, or Left / Right |
| Climb up / down (ladders, walls), drop through platforms (with Jump) | W / S, or Up / Down |
| Jump (hold for higher) | Space |
| Use the selected hotbar item toward the mouse: a weapon (or an empty slot) attacks and keeps attacking while held, a block places, a potion is drunk | Left mouse button |
| Dig the tile under the mouse (hold) | **Right mouse button** |
| Attack with your weapon, whatever is selected (hold) | F |
| Pick a hotbar slot | 1-9, 0; Ctrl + mouse wheel; mouse wheel over the hotbar; click a slot |
| Zoom | Mouse wheel; = and - |
| Interact: hold at a campfire to rest, sleep in a bed, kindle at a shrine, hold by a downed friend to haul them up, wake after dying | E |
| Quick spells: hold to aim (areas show where they land), let go to cast | Q, R, T, G |
| Dash (with the Dash spark) | Shift, or tap a direction twice |
| Inventory and paper doll | Tab or I |
| Character sheet | C |
| Constellation | K |
| Spells (assign Q R T G) | B |
| Choices waiting (level-ups, Knacks) | U |
| Show or hide the world-history log | L |
| Close the top screen | Esc |
| Debug, host only: one game hour / one game day passes | F6 / F7 |

Pickup is automatic. Screens never pause the game (it is co-op): the world runs behind them
and the movement keys still work, but clicks on (or around) a screen never dig or attack.

In the inventory: click to pick up and click to put down (or drag); Shift-click wears a piece
of gear (or takes it off); right-click drinks, wears or bonds (bonding needs a campfire near);
click outside the panel to drop what you hold. Ten ring slots, five under each hand.

A game day lasts 20 real minutes. You carry a torch (the Lantern spark widens it); caves are
dark without one.

## Screens

- **HUD**: hit points, level and class level, experience with a mark for what the next level
  gives, Hit Point Dice, spell slots, action / bonus / reaction timers, the hotbar, quick
  spells, conditions, coin, the clock, toasts, and a badge when choices wait.
- **In the world**: damage, healing, misses, crits and saves float up; monsters' wind-ups show
  as inked shapes; nameplates with hit points (elite, champion and boss frames); loot lies on
  the ground as glinting cards.
- **Inventory** (Tab), **character sheet** (C), **constellation** (K: your sparks as stars;
  kindle at a shrine), **spells** (B), **choices** (U: class-level picks and Knack cards).

`tools/fetch_fonts.sh` (run by `tools/bootstrap.sh`) fetches the two OFL fonts the interface
uses; without them it falls back to the engine font.

## Known limits

- Nobody had played M2 before this build: combat feel, wind-up dodging at real latency, the
  revive hold, inventory dragging and spell aiming want a human's judgement.
- About two thirds of SRD magic items and spells are text only or refused; no opportunity
  attacks, two-weapon fighting, grapples, Action Surge or monster spellcasting yet.
- XP pacing: early levels take about 5-8 minutes, but the deep bands level too fast (the
  whole climb to 100 is about 10 hours, not the 40 planned). See
  [docs/tracks/m2-integration.md](docs/tracks/m2-integration.md).
- Caves: worldgen opens pinch points and hangs ladders in tall shafts, but about half of cave
  spots 40 tiles apart are still out of a walker's reach without digging.
- Species and background are labels only; Epic Boons, tool and language Knacks and Bonds are
  recorded but not used yet.

## Tests

```bash
godot --headless -s res://tools/run_tests.gd     # prints ALL PASS
tools/net_smoke.sh                               # two bots and a dedicated host over ENet
WORLD="gen=dev seed=3" HOST_WAIT=3 tools/net_smoke.sh   # the same on a generated world
ALL=1 tools/net_smoke.sh   # the M2 story with the director on: fight, XP, rests, downed, revive
tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=3 \
    world=/tmp/x ui_tour=/tmp/shots     # screenshots of every screen and an M2 slice
```

Balance tools (headless): `tools/arena.gd` (a build against a ranked pack), `tools/spawn_sim.gd`
(what the director spawns, kill rates), `tools/loot_sim.gd`, `tools/xp_pacing.gd`,
`tools/cave_nav.gd`.

Rules come from [godot-srd-addon](https://github.com/narfman0/godot-srd-addon), vendored as
a submodule and symlinked at `addons/srd`.

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by
Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is
licensed under the Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.
