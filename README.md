# Godspark

A co-op sidescrolling platformer set in a simulated world built on the SRD 5.2.1: a deep
Underdark, biomes with their own ecology, settlements that trade, raid and starve, and a
long road to godhood. Working title.

- Engine: Godot 4.7.1 (Forward+), GDScript.
- Status: M1, "Dig together": a generated world, co-op digging and building, day and
  night, a living world history. See [docs/plan.md](docs/plan.md) and
  [docs/architecture.md](docs/architecture.md).

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
`port=N`; `sleep=HOURS` advances the world clock at start; `timeout=S`; `shot=PATH.png
shot_after=S` saves a screenshot and quits; `ui_tour=DIR` (with `offline cheats`, under
`tools/soft_godot.sh`) drives the interface through its screens and saves a picture of each. `game/main.gd` lists them all. The world, the
clock, the world history and the players are saved on exit.

## Controls

Terraria-like: the selected hotbar item decides what the left mouse button does.
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

## Tests

```bash
godot --headless -s res://tools/run_tests.gd     # prints ALL PASS
tools/net_smoke.sh                               # two bots and a dedicated host over ENet
WORLD="gen=dev seed=3" HOST_WAIT=3 tools/net_smoke.sh   # the same on a generated world
```

Rules come from [godot-srd-addon](https://github.com/narfman0/godot-srd-addon), vendored as
a submodule and symlinked at `addons/srd`.

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by
Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is
licensed under the Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.
