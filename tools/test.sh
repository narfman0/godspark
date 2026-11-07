#!/usr/bin/env bash
# The suite in parallel: one Godot process per test file, each with its own user:// (so
# worktrees and repeat runs can't collide). Same checks as run_tests.gd, and prints ALL PASS
# on the same terms: every file exits 0, or it is listed with its failures.
#   tools/test.sh                 every test file
#   tools/test.sh life deals      only files whose name contains one of these
#   JOBS=1 LIMIT=300 tools/test.sh    processes at once; seconds allowed per file
# JOBS defaults to 8 (AGENTS.md: parallel Godot is allowed since 2026-11-07). Each process
# waits until MemAvailable is at least 2.5 GB.
cd "$(dirname "$0")/.." || exit 1
export JOBS="${JOBS:-8}" LIMIT="${LIMIT:-300}" GODOT="${GODOT:-godot}"
export LOGS="$(mktemp -d "${TMPDIR:-/tmp}/gs_test.XXXXXX")"
one() {
	while [ "$(awk '/MemAvailable/ {print $2}' /proc/meminfo)" -lt 2500000 ]; do sleep 5; done
	XDG_DATA_HOME="$(mktemp -d "$LOGS/data.XXXXXX")" timeout -k 5 "$LIMIT" \
		"$GODOT" --headless -s res://tools/run_tests.gd -- "only=$1" >"$LOGS/$1.log" 2>&1
	echo $? >"$LOGS/$1.rc"
}
export -f one
files=$(ls tests | grep -E '^test_.*\.gd$' | grep -v '^test_log\.gd$')
if [ $# -gt 0 ]; then
	files=$(echo "$files" | grep -F "$(printf '%s\n' "$@")")
fi
start=$(date +%s)
echo "$files" | xargs -P "$JOBS" -I{} bash -c 'one {}'
bad=0
for f in $files; do
	rc=$(cat "$LOGS/$f.rc" 2>/dev/null || echo missing)
	if [ "$rc" != 0 ] || ! grep -q "ALL PASS" "$LOGS/$f.log"; then
		bad=$((bad + 1))
		echo "--- $f (exit $rc, log $LOGS/$f.log)"
		grep -E "FAIL|BROKEN|SCRIPT ERROR" "$LOGS/$f.log" | head -12
	fi
done
checks=$(cat "$LOGS"/*.log | grep -E '^[0-9]+ checks, ' | awk '{s += $1} END {print s + 0}')
took=$(($(date +%s) - start))
if [ "$bad" = 0 ]; then
	rm -rf "$LOGS"
	echo "$checks checks in $(echo "$files" | wc -l) files, ${took}s, ALL PASS"
	exit 0
fi
echo "$checks checks, ${took}s, $bad FILES FAILED"
exit 1
