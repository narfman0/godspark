#!/usr/bin/env bash
# The gate a commit on main must pass: import, the whole suite, every net smoke, and the
# unseeded end-to-end tests three times. The suite runs in parallel through tools/test.sh
# (JOBS files at once); the smokes and end-to-end runs go one at a time, each waiting for
# 2.5 GB of free memory and held under a timeout. Logs go to $GATE_LOGS (default
# /tmp/godspark-gate).
#   tools/gate.sh            about 8 minutes with JOBS=8
#   E2E=test_m4_e2e,test_m5_e2e,test_m6_e2e tools/gate.sh    which end-to-end tests to repeat
cd "$(dirname "$0")/.." || exit 2
turn() {
	until [ "$(awk '/MemAvailable/ {print $2}' /proc/meminfo)" -ge 2500000 ]; do
		sleep 10
	done
}
L=${GATE_LOGS:-/tmp/godspark-gate}
E2E=${E2E:-test_m4_e2e,test_m5_e2e}
mkdir -p "$L"
echo "head $(git rev-parse --short HEAD), dirty: $(git status --short | wc -l)"
turn
timeout 120 godot --headless --import > /dev/null 2>&1; echo "import exit $?"
turn
s=$(date +%s)
timeout 900 tools/test.sh > "$L/suite.log" 2>&1
echo "suite exit $?, $(($(date +%s) - s))s"
grep -aE "FAIL|BROKEN|SCRIPT ERROR" "$L/suite.log" | head -20
grep -aE 'checks, |ALL PASS' "$L/suite.log" | tail -3
n=0
for v in "" "FIGHT=1 SPAWN=goblin-warrior:2" "RULES=1" "SPAWNS=1 SEE= WORLD='gen=dev seed=3'" "ALL=1" "LIFE=1" "DEALS=1" "WORLD_LIFE=1"; do
	turn
	s=$(date +%s)
	n=$((n+1)); eval "env $v KEEP=1 tools/net_smoke.sh" > "$L/smoke_$n.log" 2>&1
	rc=$?
	echo "smoke [$v] exit $rc, $(($(date +%s) - s))s: $(grep -aE 'NET SMOKE (PASS|FAIL)' "$L/smoke_$n.log" | tail -1)"
	[ "$rc" = 0 ] || { grep -aE "FAIL|fail|logs kept" "$L/smoke_$n.log" | cut -c1-200 | head -8; }
done
for i in 1 2 3; do
	turn
	timeout 200 godot --headless -s res://tools/run_tests.gd -- only="$E2E" > "$L/e2e$i.log" 2>&1
	echo "e2e unseeded $i exit $?: $(grep -aE '^[0-9]+ checks, ' "$L/e2e$i.log" | tail -1) $(grep -aiE 'seed' "$L/e2e$i.log" | head -1 | cut -c1-80)"
done
echo "== done"
