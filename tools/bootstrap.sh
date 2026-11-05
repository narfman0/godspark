#!/usr/bin/env bash
# Fetch everything the game can show that is not in git: Synty models and clips from the
# asset server (only what data/looks.json, data/dressing.json and the code reference) and the
# finished monster-forge monsters. Safe to re-run: present files are skipped.
# Neither step is required: with nothing fetched every actor and object falls back to a
# primitive (or is skipped, for dressing).
#   tools/bootstrap.sh            # fetch + sync all finished monsters
#   tools/bootstrap.sh --no-monsters
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
echo "== Synty assets (tools/fetch_assets.sh)"
tools/fetch_assets.sh || { echo "fetch_assets: incomplete (see above)"; status=1; }
echo "== interface fonts (tools/fetch_fonts.sh)"
tools/fetch_fonts.sh || { echo "fetch_fonts: incomplete (the engine font is used)"; status=1; }
if [[ "${1:-}" != "--no-monsters" ]]; then
	echo "== monster-forge monsters (tools/sync_monsters.py --all)"
	python3 -I tools/sync_monsters.py --all || { echo "sync_monsters: some monsters failed (see above)"; status=1; }
fi
du -sh assets/meshes assets/monsters assets/props assets/fonts 2>/dev/null
exit $status
