# Godspark: agent notes

A co-op sidescroller in a simulated SRD 5.2.1 world. Godot 4.7.1, GDScript.
Read `docs/plan.md` (what and why) and `docs/architecture.md` (the contract) first.

## Rules

- **Layers.** `core/` is RefCounted-only, deterministic, headless. It never references
  `net/`, `view/` or `game/`. No global RNG in core.
- **Tests.** Every feature comes with `tests/test_*.gd` (a RefCounted with
  `run(t: TestLog)`). `godot --headless -s res://tools/run_tests.gd` must print `ALL PASS`;
  read the whole summary, not the last line. After adding a `class_name`, run
  `godot --headless --import` once so the class cache knows it.
- **Rules content** comes from the addon (`addons/srd`, a symlink into
  `vendor/godot-srd-addon`). Change rules there with GUT tests, not here.
- **Never commit art.** Fetched and generated assets are git-ignored. The game must run
  with none of them present (primitive fallbacks).
- **SRD 5.2.1 only.** No Forgotten Realms names. Setting names live in
  `data/setting/names.json`.
- **Nothing is pushed** without the user's OK.

## This machine

- A monster-forge batch is often running and RAM is tight. Run one Godot process at a
  time, check `grep MemAvailable /proc/meminfo` first (wait if under 2.5 GB), and never
  start ComfyUI.
- Screenshots go through `tools/soft_godot.sh` (CPU Vulkan, no GPU), at 1280x720 or less.
  Look at the picture you made.

## Godot 4.7 gotchas

- `trait` is a reserved word. Inner `class` declarations go at file scope. Lambdas capture
  locals by value.
- `_set` and `_get` are Object virtuals: don't reuse those names.
- A stale `.godot` class cache shows up as "Identifier not declared": run `--import`.

## Worktrees

`tools/new_worktree.sh <name>` makes `../godspark-wt/<name>` on branch `ws/<name>` with the
submodule checked out. Each track writes `docs/tracks/<name>.md`: what was built, the API
as built, deviations from architecture.md, measured numbers, open issues.
