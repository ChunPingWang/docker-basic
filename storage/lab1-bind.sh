#!/usr/bin/env bash
set -euo pipefail

WORK="${WORK:-$(mktemp -d -t storage-lab1-XXXX)}"
echo "==> Host workdir: $WORK"
echo "host: this file came from the host" > "$WORK/from-host.txt"

echo
echo "==> Run container with bind mount:  -v $WORK:/data"
docker container run --rm -v "$WORK:/data" ubuntu-storage bash -c '
  echo "[in container] mount info for /data:"
  findmnt /data || true
  echo
  echo "[in container] /data contents (host file should be visible):"
  ls -la /data
  echo
  echo "[in container] write a file from inside the container"
  echo "container: written from inside the container" > /data/from-container.txt
  echo
  echo "[in container] note: image originally seeded /data/seed.txt,"
  echo "               but the bind mount overlays the image content,"
  echo "               so seed.txt is hidden here."
'

echo
echo "==> Back on host. Files in $WORK:"
ls -la "$WORK"
echo
echo "==> The file written in the container is on the host:"
cat "$WORK/from-container.txt"

echo
echo "Cleanup: rm -rf $WORK"
