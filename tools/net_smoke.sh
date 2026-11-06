#!/usr/bin/env bash
# Co-op smoke test over real sockets: a headless dedicated host and two headless bot
# clients on localhost. bot1 joins at once, bot2 two seconds later (a late join, after
# bot1's edits). Each bot walks, jumps, digs, places, checks, leaves, rejoins and checks
# again. Passes only if every process exits 0 and, for each bot, the host's and the bot's
# final NETCHECK lines agree on the chunk digest and on the player position (within 0.05).
# The host also spawns $SPAWN (default one goblin warrior), and bot1 must report seeing it
# with its hit points (a "BOT bot1 vitals ..." line).
#   tools/net_smoke.sh            prints NET SMOKE PASS or what differed; exit 0 on pass
#   KEEP=1 tools/net_smoke.sh     keep the logs
#   WORLD="gen=dev seed=3" tools/net_smoke.sh   on a generated world (default gen=test)
#   SPAWN=goblin-warrior:1 SEE="Goblin Warrior monster 10/10" tools/net_smoke.sh   (defaults)
#   SPAWNS=1 WORLD="gen=dev seed=3" SEE= tools/net_smoke.sh   the monsters' spawn director on a
#                                 generated world (bots may fight or fall; the run must finish
#                                 with matching state); the host prints "HOSTSTATS monsters ..."
#   FIGHT=1 SPAWN=goblin-warrior:2 tools/net_smoke.sh   bot1 first attacks the spawned
#                                 monsters (on open ground, SPAWN_DX=-44) until they die (combat
#                                 track); it must report "BOT bot1 fight killed=N ... done"
#   RULES=1 tools/net_smoke.sh    the rules variant: host with cheats; both bots level to 24,
#                                 short-rest at a campfire and sleep in beds (the night passes
#                                 when both are in), bot1 is downed and revived by bot2, then
#                                 dies and respawns at its bed; the level survives the rejoin
#   LIFE=1 tools/net_smoke.sh     Life on a generated world: the bots stand in the spawn town
#                                 while a debug-forced raid arrives (host life_raid=4); the town
#                                 must materialize and the run end with matching state
#   ALL=1 tools/net_smoke.sh      everything at once on a generated world with the director on:
#                                 the host spawns a ranked goblin pack (pack=, the director's path)
#                                 and gives 10x kill XP; a fighter and a wizard fight it (kills and
#                                 XP), then run the whole rules scenario (rests, night, downed,
#                                 revived, respawn) and rejoin with their level
set -u
cd "$(dirname "$0")/.."

GODOT=${GODOT:-godot}
RULES=${RULES:-0}
ALL=${ALL:-0}
if [ "$ALL" = 1 ]; then
	LIMIT=${LIMIT:-240}
	WORLD=${WORLD:-gen=dev seed=3}
	SPAWNS=${SPAWNS:-1}
	SPAWN=${SPAWN:-goblin-warrior:0}
	SPAWN_DX=${SPAWN_DX:-16}
	SEE=${SEE:-Goblin Warrior}
	FIGHT=${FIGHT:-2}
	HOST_EXTRA="cheats xp=10 pack=goblin-warrior ${ALL_EXTRA:-}"
	# places=0: with Life the spawn town's people and the fights around it make the bots' place
	# step flaky (docs/tracks/life.md, open issues); placing is checked by the other variants
	BOT1_EXTRA="rules=1 rules_role=down places=0"
	BOT2_EXTRA="rules=1 rules_role=revive fight=2 places=0"
	RULES=1
fi
LIFE=${LIFE:-0}
if [ "$LIFE" = 1 ]; then
	WORLD=${WORLD:-gen=dev seed=3}
	SPAWN=${SPAWN:-goblin-warrior:0}
	SEE=${SEE:-guard of}
	SPAWNS=${SPAWNS:-0}
	HOST_EXTRA="${HOST_EXTRA:-} life_raid=4"
fi
if [ "$RULES" = 1 ] && [ "$ALL" != 1 ]; then
	LIMIT=${LIMIT:-90}
	HOST_EXTRA="cheats"
	BOT1_EXTRA="rules=1 rules_role=down"
	BOT2_EXTRA="rules=1 rules_role=revive"
fi
HOST_EXTRA=${HOST_EXTRA:-}
BOT1_EXTRA=${BOT1_EXTRA:-}
BOT2_EXTRA=${BOT2_EXTRA:-}
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
SPAWN=${SPAWN:-goblin-warrior:1}
SEE=${SEE:-Goblin Warrior monster 10/10}
# shellcheck disable=SC2086
FIGHT=${FIGHT:-0}
# FIGHT: the test world's wooden ledges start 24 tiles left of the spawn; put the pack on open ground
SPAWN_DX=${SPAWN_DX:-$([ "$FIGHT" != 0 ] && echo -44 || echo -24)}
# shellcheck disable=SC2086
SPAWNS_OPT=()
if [ -n "${SPAWNS:-}" ]; then
	SPAWNS_OPT=(spawns="$SPAWNS")
fi
run host dedicated $WORLD port="$PORT" expect=2 world="$LOGS/world" spawn="$SPAWN" spawn_dx="$SPAWN_DX" "${SPAWNS_OPT[@]}" $HOST_EXTRA
sleep "${HOST_WAIT:-1.5}"
# shellcheck disable=SC2086
run bot1 join=127.0.0.1:"$PORT" bot name=bot1 digs=4 places=3 dir=1 fight="$FIGHT" $BOT1_EXTRA
# shellcheck disable=SC2086
run bot2 join=127.0.0.1:"$PORT" bot name=bot2 digs=4 places=4 dir=-1 delay=2 class=wizard $BOT2_EXTRA

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
if [ -n "$SEE" ] && ! grep -q "^BOT bot1 vitals .*$SEE" "$LOGS/bot1.log"; then
	fail+=("bot1 never reported seeing \"$SEE\"")
fi
if [ "$ALL" = 1 ]; then
	if ! grep -qh "^BOT bot[12] fight killed=[1-9].* xp=[1-9]" "$LOGS/bot1.log" "$LOGS/bot2.log"; then
		fail+=("all: no bot killed something and got XP: $(grep -h '^BOT bot. fight' "$LOGS/bot1.log" "$LOGS/bot2.log")")
	fi
	if ! grep -q "^spawned champion" "$LOGS/host.log"; then
		fail+=("all: the host did not spawn the ranked pack")
	fi
elif [ "$FIGHT" != 0 ] && ! grep -q "^BOT bot1 fight killed=[1-9].* done" "$LOGS/bot1.log"; then
	fail+=("bot1 did not kill the spawned monsters: $(grep -h '^BOT bot1 fight' "$LOGS/bot1.log")")
fi
if [ "$RULES" = 1 ]; then
	WAITER="bot1 rules waiting for bot2"
	if [ "$ALL" = 1 ]; then   # with fights in between, either bot may get to bed first
		grep -qh "^BOT bot[12] rules waiting for bot[12]" "$LOGS/bot1.log" "$LOGS/bot2.log" || fail+=("all: no bot waited in bed for the other")
		WAITER="bot1 rules slept"
	fi
	for want in "bot1 rules short_rest" "bot2 rules short_rest" "$WAITER" "bot1 rules slept" \
			"bot2 rules slept" "bot1 rules downed" "bot2 rules revived bot1" "bot1 rules revived" \
			"bot1 rules respawned at bed" "bot1 rules rejoin ok level=24" "bot2 rules rejoin ok level=24"; do
		if ! grep -qh "^BOT $want" "$LOGS/bot1.log" "$LOGS/bot2.log"; then
			fail+=("rules: no \"BOT $want\" line")
		fi
	done
fi
grep -h "^spawned" "$LOGS/host.log" | sed 's/^/  host /'
grep -h "^SRD content\|^\[host\] SRD content" "$LOGS/host.log" | sed 's/^/  /'
if [ "${SPAWNS:-0}" != 0 ] && ! grep -q "^HOSTSTATS monsters: director true, spawned [1-9]" "$LOGS/host.log"; then
	fail+=("the spawn director spawned nothing: $(grep -h '^HOSTSTATS monsters' "$LOGS/host.log")")
fi
if [ "$LIFE" = 1 ]; then
	grep -h "^LIFE" "$LOGS/host.log" | sed 's/^/  host /'
	grep -q "^LIFE cheat: raid [0-9]" "$LOGS/host.log" || fail+=("life: the raid was not sent")
	grep -q "^HOSTSTATS life: towns [1-9][0-9]*, .* spawned [1-9]" "$LOGS/host.log" || fail+=("life: no town materialized: $(grep -h '^HOSTSTATS life' "$LOGS/host.log")")
fi
grep -h "^HOSTSTATS" -A 14 "$LOGS/host.log" | grep -v "^saved" | sed 's/^/  /'

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
