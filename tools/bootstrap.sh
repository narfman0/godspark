#!/usr/bin/env bash
# Fetch everything the game can show that is not in git: Synty models and clips from the
# asset server (only what data/looks.json, data/dressing.json and the code reference) and the
# finished monster-forge monsters with their props. Safe to re-run: present files are skipped,
# and a monster whose forge manifest and file sizes did not change costs two small requests.
# Neither step is required: with nothing fetched every actor and object falls back to a
# primitive (or is skipped, for dressing).
#   tools/bootstrap.sh                 # fetch + sync every usable forge monster over HTTP
#   tools/bootstrap.sh --no-monsters
#   tools/bootstrap.sh --local         # monsters from a local monster-forge checkout's out/
# The forge viewer: MONSTER_FORGE_URL (default http://192.168.1.12:8787, see
# tools/sync_monsters.py). LOD0 only (about 3.5 GB for 311 monsters). Unreachable: the game uses
# its stand-ins. docs/tracks/forge-art.md has what a re-sync changes.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
echo "== Synty assets (tools/fetch_assets.sh)"
tools/fetch_assets.sh || { echo "fetch_assets: incomplete (see above)"; status=1; }
echo "== interface fonts (tools/fetch_fonts.sh)"
tools/fetch_fonts.sh || { echo "fetch_fonts: incomplete (the engine font is used)"; status=1; }
case "${1:-}" in
	--no-monsters) ;;
	--local)
		echo "== monster-forge monsters (tools/sync_monsters.py --all, local checkout)"
		python3 -I tools/sync_monsters.py --all || { echo "sync_monsters: some monsters failed (see above)"; status=1; } ;;
	*)
		echo "== monster-forge monsters (tools/sync_monsters.py --http --all)"
		python3 -I tools/sync_monsters.py --http --all || { echo "sync_monsters: some monsters failed (see above and assets/monsters/_sync.json)"; status=1; } ;;
esac
du -sh assets/meshes assets/monsters assets/props assets/fonts 2>/dev/null
exit $status
