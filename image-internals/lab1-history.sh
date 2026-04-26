#!/usr/bin/env bash
set -euo pipefail

echo "==> Every Dockerfile instruction creates a layer (unless squashed)."
echo "==> Look at how real images are built up:"
echo

docker pull ubuntu:22.04 >/dev/null
docker pull alpine:3.19 >/dev/null

echo "------------------------------------------------------------"
echo "ubuntu:22.04 — official Ubuntu base"
echo "------------------------------------------------------------"
docker history ubuntu:22.04

echo
echo "------------------------------------------------------------"
echo "alpine:3.19 — alpine base (notice it is much smaller)"
echo "------------------------------------------------------------"
docker history alpine:3.19

echo
echo "------------------------------------------------------------"
echo "Image config — what runs by default, env vars, etc."
echo "------------------------------------------------------------"
docker inspect ubuntu:22.04 --format '{{json .Config}}' | jq

echo
echo "==> Each layer is content-addressable (sha256). Two images sharing a base"
echo "==> share those layers on disk — that is why pulling a 2nd image based on"
echo "==> ubuntu:22.04 only downloads the new layers."
