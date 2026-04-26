#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t image-lab2-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> An image is just a tarball with a specific structure."
echo "==> Use 'docker save' to dump it, then unpack and look inside."
echo

echo "==> Save alpine:3.19 to a .tar:"
docker save alpine:3.19 -o "$WORK/alpine.tar"
ls -lh "$WORK/alpine.tar"

echo
echo "==> Top-level entries in the tar:"
tar -tf "$WORK/alpine.tar" | head -10

echo
echo "==> Extract and look at structure:"
mkdir "$WORK/extracted"
tar -C "$WORK/extracted" -xf "$WORK/alpine.tar"
ls -la "$WORK/extracted"

echo
echo "==> manifest.json (what the image points at):"
cat "$WORK/extracted/manifest.json" | jq

echo
echo "==> The blobs/sha256/ directory holds layers + config:"
ls -lh "$WORK/extracted/blobs/sha256/" | head -10

echo
echo "==> Pick a layer blob and peek inside:"
LAYER_BLOB=$(jq -r '.[0].Layers[0]' "$WORK/extracted/manifest.json")
echo "Layer file: $LAYER_BLOB"
echo "Top of that layer (it is itself a tar of a rootfs):"
tar -tf "$WORK/extracted/$LAYER_BLOB" | head -10

echo
echo "==> Punchline: an OCI image = manifest pointing at a config blob"
echo "==> + N layer blobs (each is a tar). Nothing magic."
