#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This lab manipulates cgroupfs and must run as root (use sudo)." >&2
    exit 1
fi

if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
    echo "This system isn't using cgroup v2 (no /sys/fs/cgroup/cgroup.controllers)." >&2
    echo "This lab assumes cgroup v2; modern Ubuntu / Fedora are fine." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is needed for the memory allocation step. Install it and retry." >&2
    exit 1
fi

CG=/sys/fs/cgroup/cgroups-lab5
rmdir "$CG" 2>/dev/null || true
mkdir "$CG"

echo "==> Root cgroup controllers available on this system:"
cat /sys/fs/cgroup/cgroup.controllers

echo
echo "==> Make sure memory + pids are delegated to children (idempotent):"
echo "+memory +pids" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
echo "==> Controllers now usable inside our new cgroup:"
cat $CG/cgroup.controllers

echo
echo "==> Set memory.max=20M, memory.swap.max=0 (force OOM, no swap escape), pids.max=10"
echo "20M" > $CG/memory.max
echo "0"   > $CG/memory.swap.max 2>/dev/null || echo "(memory.swap.max not available — host may not have swap accounting; OOM may not trigger)"
echo "10"  > $CG/pids.max

echo
echo "==> Final settings:"
grep -H '' $CG/memory.max $CG/memory.swap.max $CG/pids.max 2>/dev/null

echo
echo "==> Spawn a child shell, attach it to the cgroup, allocate 100MB."
echo "==> Expect: kernel OOM-kills the child the moment it crosses 20MB."
echo

set +e
(
    # The subshell joins the new cgroup, then exec replaces it with python3.
    echo $BASHPID > $CG/cgroup.procs
    exec python3 -c '
import os
print(f"[child pid={os.getpid()}] now running inside the cgroup. /proc/self/cgroup says:")
with open("/proc/self/cgroup") as f:
    print("  " + f.read().strip())
print("[child] allocating 100MB...")
data = bytearray(100 * 1024 * 1024)
print("[child] survived — should not happen!")
' 2>&1
)
rc=$?
set -e
echo
echo "==> Child exit code: $rc  (137 = SIGKILL from OOM)"

echo
echo "==> memory.events shows what the kernel did:"
cat $CG/memory.events 2>/dev/null || true

echo
echo "Cleanup:"
echo "  sudo rmdir $CG"
