#!/usr/bin/env bash
set -euo pipefail

echo "==> Observe the rootful Docker setup that you are running right now."
echo

echo "------------------------------------------------------------"
echo "1. dockerd runs as root on the host:"
echo "------------------------------------------------------------"
ps -eo pid,user,cmd | grep -E '[d]ockerd' | head -3
echo "  ^ user is 'root' — Docker daemon needs root for namespace / cgroup ops"

echo
echo "------------------------------------------------------------"
echo "2. containerd also runs as root:"
echo "------------------------------------------------------------"
ps -eo pid,user,cmd | grep -E '[c]ontainerd' | head -3

echo
echo "------------------------------------------------------------"
echo "3. Container 'root' maps to host root:"
echo "------------------------------------------------------------"
docker run --rm ubuntu:22.04 bash -c '
echo "[in container]"; id
echo "[in container] /proc/self/uid_map (whose UIDs are visible):"
cat /proc/self/uid_map
'

echo
echo "------------------------------------------------------------"
echo "4. So if a container can escape, it has host root:"
echo "------------------------------------------------------------"
echo "    docker run --rm -v /:/host ubuntu cat /host/etc/shadow"
echo "    ^ this would actually work as root (capabilities restrict it,"
echo "      seccomp restricts it, but architecturally — container root = host root)"
echo
echo "==> This is the 'rootful' threat model, and why people want rootless."
