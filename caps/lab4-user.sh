#!/usr/bin/env bash
set -euo pipefail

echo "==> --user changes the UID inside the container. Non-root means almost no"
echo "==> capabilities, even if the original image was meant to run as root."
echo

echo "------------------------------------------------------------"
echo "Default (root, UID 0):"
echo "------------------------------------------------------------"
docker container run --rm ubuntu-caps bash -c '
id
echo "CapEff:"
capsh --decode=$(grep CapEff /proc/self/status | cut -f2) | head -3
'

echo
echo "------------------------------------------------------------"
echo "--user 1000:1000 — UID is now 1000, capabilities collapse to nothing:"
echo "------------------------------------------------------------"
docker container run --rm --user 1000:1000 ubuntu-caps bash -c '
id
echo "CapEff:"
grep CapEff /proc/self/status
echo
echo "Try to write to /etc (root-owned):"
echo test > /etc/forbidden 2>&1 || echo "(write blocked — non-root + DAC)"
echo
echo "Try to chown a file:"
chown 0:0 /tmp 2>&1 || echo "(chown blocked — no CAP_CHOWN since non-root has empty CapEff)"
'

echo
echo "==> Punchline: 'just run as a non-root user' is one of the cheapest, most"
echo "==> effective hardening steps. It strips capabilities, blocks low ports,"
echo "==> and prevents most container escape paths."
