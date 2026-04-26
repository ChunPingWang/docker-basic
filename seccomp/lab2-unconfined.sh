#!/usr/bin/env bash
set -euo pipefail

echo "==> Compare a syscall that the default profile blocks vs allows."
echo "==> We'll use 'unshare -U' (CLONE_NEWUSER) which Docker's default profile"
echo "==> does not allow inside the container without --security-opt or extra caps."
echo

echo "------------------------------------------------------------"
echo "Default container — try unshare -U bash:"
echo "------------------------------------------------------------"
docker container run --rm ubuntu:22.04 bash -c '
apt-get update -qq >/dev/null 2>&1 || true
unshare -U bash -c "id" 2>&1 || echo "(unshare blocked)"
' 2>&1 | tail -5

echo
echo "------------------------------------------------------------"
echo "Same image, but with seccomp=unconfined:"
echo "------------------------------------------------------------"
docker container run --rm --security-opt seccomp=unconfined ubuntu:22.04 bash -c '
unshare -U bash -c "id" 2>&1 || echo "(unshare still blocked — capability issue, not seccomp)"
' 2>&1 | tail -5

echo
echo "==> If both work the same way, your kernel allows this syscall regardless"
echo "==> of seccomp (newer Docker profiles allow CLONE_NEWUSER for unprivileged"
echo "==> users). The next labs use a custom profile to make a clearer difference."
