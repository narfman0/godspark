# Godspark

A co-op sidescrolling platformer set in a simulated world built on the SRD 5.2.1: a deep
Underdark, biomes with their own ecology, settlements that trade, raid and starve, and a
long road to godhood. Working title.

- Engine: Godot 4.7.1 (Forward+), GDScript.
- Status: M0, foundations. See [docs/plan.md](docs/plan.md) and
  [docs/architecture.md](docs/architecture.md).

```bash
git clone --recurse-submodules <this repo>
godot --headless --import
godot --headless -s res://tools/run_tests.gd     # prints ALL PASS
```

Rules come from [godot-srd-addon](https://github.com/narfman0/godot-srd-addon), vendored as
a submodule and symlinked at `addons/srd`.

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by
Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is
licensed under the Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.
