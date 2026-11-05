#!/usr/bin/env bash
# A git worktree for one workstream, with the addon submodule checked out from the local
# addon repo (so unpushed addon commits work).
#   tools/new_worktree.sh worldgen      -> ../godspark-wt/worldgen on branch ws/worldgen
set -euo pipefail
name="$1"
root="$(git rev-parse --show-toplevel)"
dest="$(dirname "$root")/godspark-wt/$name"
git -C "$root" worktree add -q "$dest" -b "ws/$name"
cd "$dest"
git config -f .git/../.gitmodules --get submodule.vendor/godot-srd-addon.url >/dev/null
git -c protocol.file.allow=always -c "url.$(dirname "$root")/godot-srd-addon.insteadOf=https://github.com/narfman0/godot-srd-addon.git" submodule update --init -q
godot --headless --import >/dev/null 2>&1 || true
echo "$dest"
