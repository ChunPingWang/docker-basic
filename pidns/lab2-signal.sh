#!/usr/bin/env bash
set -euo pipefail

NAME=pidns-lab2
docker rm -f $NAME >/dev/null 2>&1 || true

echo "==> Start sleep as PID 1 in a fresh container (no --init)"
docker run -d --rm --name $NAME ubuntu-pidns sleep 300 >/dev/null
sleep 0.3

echo
echo "==> Confirm PID 1 inside is plain sleep:"
docker exec $NAME ps -ef

echo
echo "==> Send SIGTERM to PID 1 from inside the container:"
docker exec $NAME kill -TERM 1 || true
sleep 0.3
running=$(docker inspect --format '{{.State.Running}}' $NAME 2>/dev/null || echo false)
echo "Container still running? $running"
echo "==> SIGTERM was IGNORED. The kernel protects PID 1 from default-action signals"
echo "==> when the process has not installed a handler for that signal (sleep hasn't)."

echo
echo "==> Now ask docker to stop it with a 2-second grace period:"
echo "==> docker sends SIGTERM (still ignored), waits 2s, then SIGKILL (always wins)."
start=$(date +%s.%N)
docker stop --time=2 $NAME >/dev/null
end=$(date +%s.%N)
elapsed=$(awk "BEGIN { printf \"%.2f\", $end - $start }")
echo "==> docker stop took ${elapsed}s — almost exactly the grace period."
echo "==> Punchline: a container running plain sleep / bash / node as PID 1"
echo "==>           will never react to SIGTERM. Lab 4 shows the fix (--init)."
