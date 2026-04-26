#!/usr/bin/env bash
set -euo pipefail

echo "==> Run container with a tmpfs mount at /scratch (RAM-backed, never touches disk)"
docker container run --rm --tmpfs /scratch:size=128m ubuntu-storage bash -c '
  echo "[in container] mount info for /scratch:"
  findmnt /scratch
  echo
  echo "[in container] write 64 MB into /scratch"
  dd if=/dev/zero of=/scratch/big.bin bs=1M count=64 status=none
  ls -lh /scratch
  echo
  echo "[in container] /scratch is the only place backed by tmpfs;"
  echo "               compare with /data (image layer / anonymous volume):"
  findmnt /data || true
'

echo
echo "==> Container exited. The tmpfs lived only in RAM and is gone."
echo "==> Use cases: secrets you do not want on disk, high-speed scratch space."
