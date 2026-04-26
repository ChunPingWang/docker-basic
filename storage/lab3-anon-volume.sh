#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-storage-lab3}"

echo "==> The image declares VOLUME [\"/data\"]."
echo "==> When we run it WITHOUT --rm and WITHOUT specifying a volume,"
echo "==> Docker creates an anonymous volume to back /data."
echo

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker container run -d --name "$NAME" ubuntu-storage sleep 30 >/dev/null

echo "==> docker inspect Mounts:"
docker inspect --format '{{ json .Mounts }}' "$NAME" | jq

ANON_VOL="$(docker inspect --format '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }}{{ end }}{{ end }}' "$NAME")"
echo
echo "==> Anonymous volume name: $ANON_VOL"
echo "==> It shows up in 'docker volume ls':"
docker volume ls | grep -E "VOLUME|$ANON_VOL"

echo
echo "==> Stop and remove the container WITHOUT --rm:"
docker stop "$NAME" >/dev/null
docker rm "$NAME" >/dev/null

echo
echo "==> Anonymous volume is left behind (this is what eats disk over time):"
docker volume ls | grep "$ANON_VOL" || echo "(volume already removed)"

echo
echo "==> Manual cleanup of the orphan:"
echo "    docker volume rm $ANON_VOL"
echo
echo "==> Tip: re-run with 'docker run --rm ...' and the anonymous volume"
echo "         is automatically removed when the container is removed."
