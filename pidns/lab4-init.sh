#!/usr/bin/env bash
set -euo pipefail

echo "==> Same scenarios as Lab 2 + Lab 3, but with --init."
echo "==> Docker injects 'tini' as PID 1; tini's job is to forward signals"
echo "==> to its child and reap any reparented zombies."
echo

# ---- Part 1: signals ----
NAME=pidns-lab4-sig
docker rm -f $NAME >/dev/null 2>&1 || true

echo "------------------------------------------------------------"
echo "Part 1: SIGTERM forwarding"
echo "------------------------------------------------------------"

docker run -d --rm --init --name $NAME ubuntu-pidns sleep 300 >/dev/null
sleep 0.3

echo
echo "==> PID tree inside (PID 1 should be tini, sleep is its child):"
docker exec $NAME ps -ef

echo
echo "==> docker stop --time=10. Expect: exits in <1s because tini relays SIGTERM"
echo "==> to sleep, and sleep (PID 2) has no PID 1 protection."
start=$(date +%s.%N)
docker stop --time=10 $NAME >/dev/null
end=$(date +%s.%N)
elapsed=$(awk "BEGIN { printf \"%.2f\", $end - $start }")
echo "==> docker stop took ${elapsed}s  (compare with Lab 2's ~2s)."

# ---- Part 2: zombies ----
echo
echo "------------------------------------------------------------"
echo "Part 2: zombie reaping"
echo "------------------------------------------------------------"
echo
echo "==> Same orphan-factory Python script, but now with --init."
echo

docker run --rm --init ubuntu-pidns python3 -c '
import os, time, subprocess

print(f"[in container] my pid = {os.getpid()}  (no longer 1 — tini is)")
print()

for i in range(10):
    pid = os.fork()
    if pid == 0:
        gpid = os.fork()
        if gpid == 0:
            time.sleep(0.2)
            os._exit(0)
        os._exit(0)
    else:
        os.waitpid(pid, 0)

time.sleep(1)

out = subprocess.run(["ps", "-e", "-o", "pid,ppid,stat,cmd"],
                    capture_output=True, text=True).stdout
print(out)

zombies = [l for l in out.splitlines()[1:]
           if len(l.split()) >= 3 and l.split()[2].startswith("Z")]
print(f"[in container] zombie count: {len(zombies)}")
'

echo
echo "==> Zombies should be 0 — tini reaped them all."
echo "==> Punchline: --init = a 1KB process (tini) that fixes both the signal"
echo "==>           problem and the zombie problem. Always use it for long-running"
echo "==>           containers whose entrypoint isn't a real init system."
