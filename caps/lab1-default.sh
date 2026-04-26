#!/usr/bin/env bash
set -euo pipefail

echo "==> What capabilities does a default Docker container have?"
echo "==> capsh decodes /proc/self/status -> CapEff (effective capability set)."
echo

docker container run --rm ubuntu-caps bash -c '
echo "[in container] root inside?"; id
echo
echo "[in container] CapEff bitmap from /proc/self/status:"
grep CapEff /proc/self/status
echo
echo "[in container] decoded:"
capsh --decode=$(grep CapEff /proc/self/status | cut -f2)
'

echo
echo "==> Compare with HOST root capabilities (~all enabled):"
sudo -n true 2>/dev/null && {
  echo "  CapEff (host root):"
  grep CapEff /proc/self/status 2>/dev/null || echo "  (run this as root to compare)"
} || echo "  (skip — needs passwordless sudo)"

echo
echo "==> Punchline: Docker containers do NOT get all capabilities by default."
echo "==> The default set excludes things like SYS_ADMIN, SYS_TIME, NET_ADMIN, SYS_MODULE."
echo "==> 'Root inside the container' is a SUBSET of root on the host."
