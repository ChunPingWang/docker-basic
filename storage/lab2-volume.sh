#!/usr/bin/env bash
set -euo pipefail

VOL="${VOL:-storage-lab2-vol}"

echo "==> Create a named volume: $VOL"
docker volume rm "$VOL" >/dev/null 2>&1 || true
docker volume create "$VOL" >/dev/null
docker volume inspect "$VOL"

echo
echo "==> First container: write data into the named volume"
docker container run --rm -v "$VOL:/data" ubuntu-storage bash -c '
  echo "[in container] /data initially contains the image seed copied into the empty volume:"
  ls -la /data
  echo
  echo "[in container] add a new file"
  echo "persisted via named volume" > /data/note.txt
  ls -la /data
'

echo
echo "==> Second container (different lifetime): the data is still there"
docker container run --rm -v "$VOL:/data" ubuntu-storage bash -c '
  echo "[in container] /data contents:"
  ls -la /data
  echo
  echo "[in container] read the note from the previous container:"
  cat /data/note.txt
'

echo
echo "==> Volume location on host (managed by Docker):"
docker volume inspect --format '{{ .Mountpoint }}' "$VOL"

echo
echo "Cleanup: docker volume rm $VOL"
