#!/usr/bin/env bash
set -euo pipefail

echo "==> Run a Python orphan-maker as PID 1 (no --init)"
echo "==> The script forks 10 children, each forks a grandchild and exits."
echo "==> Grandchildren get reparented to PID 1 (this Python). When they exit,"
echo "==> PID 1 is supposed to wait() for them — but Python doesn't unless we tell it to."
echo "==> Result: zombies pile up."
echo

docker run --rm ubuntu-pidns python3 -c '
import os, time, subprocess

print(f"[in container] my pid = {os.getpid()}  (should be 1)")
print()

for i in range(10):
    pid = os.fork()
    if pid == 0:
        # Child: fork a grandchild and immediately exit. Grandchild becomes
        # orphan, gets reparented to PID 1.
        gpid = os.fork()
        if gpid == 0:
            time.sleep(0.2)
            os._exit(0)
        os._exit(0)
    else:
        # Parent: reap our direct child (so the *child* is not a zombie).
        os.waitpid(pid, 0)

# Give grandchildren time to exit and turn into zombies.
time.sleep(1)

print("[in container] processes visible after the orphan factory ran:")
out = subprocess.run(["ps", "-e", "-o", "pid,ppid,stat,cmd"],
                    capture_output=True, text=True).stdout
print(out)

zombies = [l for l in out.splitlines()[1:]
           if len(l.split()) >= 3 and l.split()[2].startswith("Z")]
print(f"[in container] zombie count: {len(zombies)}")
'

echo
echo "==> Without an init that reaps, every short-lived grandchild that ends up"
echo "==> reparented to PID 1 will sit as a zombie until the container dies."
echo "==> In long-running containers (CI runners, dev shells) this leaks PIDs."
