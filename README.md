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
shot_after=S` saves a screenshot and quits. `game/main.gd` lists them all. The world, the
clock, the world history and the players are saved on exit.

## Controls

| Action | Keys |
|---|---|
| Move left / right | A / D, or Left / Right |
| Climb up / down (ladders, walls), drop through platforms (with Jump) | W / S, or Up / Down |
| Jump (hold for higher) | Space |
| Dig the tile under the mouse (hold) | Left mouse button |
| Place the selected block under the mouse | Right mouse button |
| Select block: wood, platform, torch, ladder | 1, 2, 3, 4 |
| Zoom | Mouse wheel |
| Show or hide the world-history log | C |
| Debug, host only: one game hour / one game day passes | F6 / F7 |

A game day lasts 20 real minutes. You carry a torch; caves are dark without one.

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
