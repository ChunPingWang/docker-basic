#!/usr/bin/env bash
set -euo pipefail

echo "==> Run with --memory=64m --memory-swap=64m (no swap allowed)."
echo "==> Inside, ask Python to allocate 200MB as a bytearray (initialized to 0,"
echo "==> which forces every page to be backed by physical memory)."
echo "==> Expect: kernel OOM-kills the process, container exits 137."
echo

set +e
docker container run --rm --memory=64m --memory-swap=64m ubuntu-cgroups \
    python3 -c '
limit = open("/sys/fs/cgroup/memory.max").read().strip()
print("[in container] memory.max = " + limit)
print("[in container] allocating 200MB...")
data = bytearray(200 * 1024 * 1024)
print("[in container] survived — should NOT happen with a 64MB cap!")
' 2>&1
rc=$?
set -e
echo
echo "==> Container exit code: $rc  (137 = SIGKILL from OOM)"

echo
echo "==> What the container saw as its memory limit:"
docker container run --rm --memory=64m ubuntu-cgroups bash -c '
  echo "memory.max:     $(cat /sys/fs/cgroup/memory.max)"
  echo "memory.current: $(cat /sys/fs/cgroup/memory.current)"
'
