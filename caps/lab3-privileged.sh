#!/usr/bin/env bash
set -euo pipefail

echo "==> --privileged is the nuclear option: ALL capabilities, all device access,"
echo "==> seccomp / AppArmor turned off. Compare a default container vs --privileged."
echo

echo "------------------------------------------------------------"
echo "Default container — try mount /proc inside:"
echo "------------------------------------------------------------"
docker container run --rm ubuntu-caps bash -c '
mount -t proc proc /mnt 2>&1 | head -3 || echo "(mount failed — no CAP_SYS_ADMIN)"
echo
echo "CapEff bits set:"
capsh --decode=$(grep CapEff /proc/self/status | cut -f2) | head -5
'

echo
echo "------------------------------------------------------------"
echo "--privileged container — same mount works:"
echo "------------------------------------------------------------"
docker container run --rm --privileged ubuntu-caps bash -c '
mkdir -p /mnt/x
mount -t proc proc /mnt/x && echo "(mount succeeded — privileged)"
ls /mnt/x | head -5
umount /mnt/x
echo
echo "CapEff bits set (notice the count is much higher):"
capsh --decode=$(grep CapEff /proc/self/status | cut -f2) | head -5
'

echo
echo "==> Punchline: --privileged makes the container effectively a process on host."
echo "==> Use it only when you absolutely must (Docker-in-Docker, low-level device IO)."
echo "==> For one specific need, prefer --cap-add=<just-that-one>."
