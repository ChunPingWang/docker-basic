#!/usr/bin/env bash
set -euo pipefail

echo "==> Demonstrate what each capability actually unlocks by dropping it."
echo "==> We pick the most visible: NET_RAW (raw sockets, used by ping)."
echo

echo "------------------------------------------------------------"
echo "Default container — ping works:"
echo "------------------------------------------------------------"
docker container run --rm ubuntu-caps ping -c 2 -W 2 8.8.8.8 2>&1 | tail -5 || true

echo
echo "------------------------------------------------------------"
echo "--cap-drop=NET_RAW — ping breaks (no raw sockets allowed):"
echo "------------------------------------------------------------"
docker container run --rm --cap-drop=NET_RAW ubuntu-caps ping -c 2 -W 2 8.8.8.8 2>&1 | tail -5 || true

echo
echo "------------------------------------------------------------"
echo "--cap-drop=ALL --cap-add=NET_RAW — only ping is allowed:"
echo "------------------------------------------------------------"
docker container run --rm --cap-drop=ALL --cap-add=NET_RAW ubuntu-caps bash -c '
echo "[in container] CapEff (decoded):"
capsh --decode=$(grep CapEff /proc/self/status | cut -f2)
echo
echo "[in container] ping should still work:"
ping -c 1 -W 2 8.8.8.8 | tail -3
echo
echo "[in container] but chown should NOT (CAP_CHOWN was dropped):"
chown 1:1 /etc/hostname 2>&1 || echo "(chown failed as expected)"
'

echo
echo "==> Punchline: capabilities are surgical — drop the ones you do not need,"
echo "==> add back only what is essential. This is much safer than running"
echo "==> --privileged (which gives everything)."
