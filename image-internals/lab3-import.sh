#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t image-lab3-XXXX)"
trap "rm -rf $WORK" EXIT

NAME=imagelab3-temp
docker rm -f $NAME >/dev/null 2>&1 || true

echo "==> Demo: build an image WITHOUT a Dockerfile."
echo "==> Strategy: run a container, modify it, 'docker export' its filesystem,"
echo "==> then 'docker import' the tarball as a new image."
echo

echo "==> Run a temp ubuntu container and bake a file into it:"
docker run -d --name $NAME ubuntu:22.04 sleep 60 >/dev/null
docker exec $NAME bash -c 'echo "baked from CLI at $(date -Iseconds)" > /baked.txt'

echo
echo "==> Export the container fs:"
docker export $NAME -o "$WORK/baked.tar"
docker rm -f $NAME >/dev/null
ls -lh "$WORK/baked.tar"
echo
echo "==> Tar contents (first 8 entries):"
tar -tf "$WORK/baked.tar" 2>/dev/null | head -8 || true

echo
echo "==> Import as a brand-new image, with a CMD set via --change:"
docker import --change 'CMD ["cat", "/baked.txt"]' \
              "$WORK/baked.tar" baked-image:v1

docker images baked-image

echo
echo "==> Run it:"
docker run --rm baked-image:v1

echo
echo "==> Punchline: any tarball with a usable rootfs becomes an image."
echo "==> Dockerfile is just a friendly recipe; the on-disk format is plain tar + JSON."

docker rmi baked-image:v1 >/dev/null
