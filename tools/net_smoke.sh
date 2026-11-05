#!/usr/bin/env bash
# Co-op smoke test over real sockets: a headless dedicated host and two headless bot
# clients on localhost. bot1 joins at once, bot2 two seconds later (a late join, after
# bot1's edits). Each bot walks, jumps, digs, places, checks, leaves, rejoins and checks
# again. Passes only if every process exits 0 and, for each bot, the host's and the bot's
# final NETCHECK lines agree on the chunk digest and on the player position (within 0.05).
#   tools/net_smoke.sh            prints NET SMOKE PASS or what differed; exit 0 on pass
#   KEEP=1 tools/net_smoke.sh     keep the logs
#   WORLD="gen=dev seed=3" tools/net_smoke.sh   on a generated world (default gen=test)
set -u
cd "$(dirname "$0")/.."

GODOT=${GODOT:-godot}
LIMIT=${LIMIT:-60}            # seconds each process may run
LOGS=$(mktemp -d "${TMPDIR:-/tmp}/net_smoke.XXXXXX")
PIDS=()

cleanup() {
	for p in "${PIDS[@]}"; do
		kill "$p" 2>/dev/null
	done
	sleep 0.3
	for p in "${PIDS[@]}"; do
		kill -9 "$p" 2>/dev/null
	done
	wait 2>/dev/null
	if [ "${KEEP:-0}" = 1 ]; then
		echo "logs kept in $LOGS"
	else
		rm -rf "$LOGS"
	fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
if [ "$avail_kb" -lt 2500000 ]; then
	echo "NET SMOKE SKIP: only $((avail_kb / 1024)) MB available (need 2500)"
	exit 2
fi

PORT=$(python3 -c 'import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])')

run() {   # run NAME ARGS... : a headless Godot in the background, logging to $LOGS/NAME.log
	local name=$1
	shift
	timeout -k 5 "$LIMIT" "$GODOT" --headless --path . -- "$@" timeout=$((LIMIT - 5)) >"$LOGS/$name.log" 2>&1 &
	PIDS+=($!)
}

echo "net smoke: port $PORT, logs $LOGS"
WORLD=${WORLD:-gen=test}
# shellcheck disable=SC2086
run host dedicated $WORLD port="$PORT" expect=2 world="$LOGS/world"
sleep "${HOST_WAIT:-1.5}"
run bot1 join=127.0.0.1:"$PORT" bot name=bot1 digs=4 places=3 dir=1
run bot2 join=127.0.0.1:"$PORT" bot name=bot2 digs=3 places=4 dir=-1 delay=2

fail=()
names=(host bot1 bot2)
for i in "${!PIDS[@]}"; do
	wait "${PIDS[$i]}"
	code=$?
	if [ "$code" -ne 0 ]; then
		fail+=("${names[$i]} exited $code")
	fi
done
PIDS=()

for bot in bot1 bot2; do
	h=$(grep -o "NETCHECK host name=$bot tag=final .*" "$LOGS/host.log" | tail -1)
	c=$(grep -o "NETCHECK client name=$bot tag=final .*" "$LOGS/$bot.log" | tail -1)
	if [ -z "$h" ] || [ -z "$c" ]; then
		fail+=("$bot: missing final NETCHECK (host: ${h:-none}; client: ${c:-none})")
		continue
	fi
	hh=$(sed -E 's/.* hash=([0-9a-f]+).*/\1/' <<<"$h")
	ch=$(sed -E 's/.* hash=([0-9a-f]+).*/\1/' <<<"$c")
	hn=$(sed -E 's/.* chunks=([0-9]+).*/\1/' <<<"$h")
	hp=$(sed -E 's/.* pos=([-0-9.]+,[-0-9.]+).*/\1/' <<<"$h")
	cp=$(sed -E 's/.* pos=([-0-9.]+,[-0-9.]+) .*/\1/' <<<"$c")
	if [ "$hh" != "$ch" ]; then
		fail+=("$bot: chunk digest differs: host $hh, client $ch")
	fi
	if ! awk -v a="$hp" -v b="$cp" 'BEGIN { split(a, p, ","); split(b, q, ",");
			dx = p[1] - q[1]; dy = p[2] - q[2]; exit !(dx * dx + dy * dy <= 0.05 * 0.05) }'; then
		fail+=("$bot: position differs: host $hp, client $cp")
	fi
	echo "  $bot: $hn chunks, digest ${hh:0:16}..., host pos $hp, client pos $cp"
	grep -h "^BOT $bot " "$LOGS/$bot.log" | sed 's/^/    /'
done
grep -h "^HOSTSTATS" -A 12 "$LOGS/host.log" | grep -v "^saved" | sed 's/^/  /'

sleep 0.2
strays=$(pgrep -f -- "--path . -- .*127.0.0.1:$PORT|port=$PORT" || true)
if [ -n "$strays" ]; then
	fail+=("stray processes: $strays")
	kill -9 $strays 2>/dev/null
fi

if [ ${#fail[@]} -eq 0 ]; then
	echo "NET SMOKE PASS"
	exit 0
fi
echo "NET SMOKE FAIL"
for f in "${fail[@]}"; do
	echo "  - $f"
done
for n in host bot1 bot2; do
	echo "---- $n (last 15 lines)"
	tail -15 "$LOGS/$n.log"
done
exit 1
