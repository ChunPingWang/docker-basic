#!/usr/bin/env bash
set -euo pipefail

echo "==> Run with --pids-limit=20 and try to fork 50 child processes from Python."
echo "==> Expect: about 17–18 succeed (the others are baseline bash + python),"
echo "==> the rest get OSError 'Resource temporarily unavailable' from fork()."
echo
echo "==> (We use Python rather than bash because bash gives up after 8 retries"
echo "==>  and aborts the whole script when fork keeps returning EAGAIN.)"
echo

docker container run --rm --pids-limit=20 ubuntu-cgroups python3 -c '
import os, time

pids_max = open("/sys/fs/cgroup/pids.max").read().strip()
print(f"[in container] pids.max from cgroupfs: {pids_max}")
print()

succeeded = 0
failed = 0
for i in range(50):
    try:
        pid = os.fork()
        if pid == 0:
            time.sleep(30)
            os._exit(0)
        succeeded += 1
    except OSError as e:
        failed += 1

current = open("/sys/fs/cgroup/pids.current").read().strip()
print(f"[in container] forks succeeded: {succeeded}")
print(f"[in container] forks failed:    {failed}")
print(f"[in container] pids.current:    {current}")
print()
print("[in container] this is exactly what stops a fork bomb:")
print("               the kernel refuses fork() once pids.current hits pids.max.")
'
