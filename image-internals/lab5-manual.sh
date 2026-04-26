#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t image-lab5-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> Demo: build an image WITHOUT Dockerfile and WITHOUT 'docker build'."
echo "==> Take the static hello binary from Lab 4's hello-scratch image,"
echo "==> hand-craft a tar, and 'docker import' it."
echo

if ! docker image inspect hello-scratch:latest >/dev/null 2>&1; then
    echo "==> Need hello-scratch from Lab 4 first. Building it..."
    cat > "$WORK/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { printf("hello from a hand-crafted image\n"); return 0; }
EOF
    cat > "$WORK/Dockerfile.scratch" <<'EOF'
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc-dev
COPY hello.c /hello.c
RUN gcc -static -o /hello /hello.c
FROM scratch
COPY --from=builder /hello /hello
EOF
    docker build -q -f "$WORK/Dockerfile.scratch" -t hello-scratch "$WORK" >/dev/null
fi

echo "==> Pull the static binary out of hello-scratch:latest"
CID=$(docker create hello-scratch:latest fakeentrypoint)
docker cp "$CID:/hello" "$WORK/hello"
docker rm "$CID" >/dev/null

echo "==> Binary size on host:"
ls -lh "$WORK/hello"
file "$WORK/hello" 2>/dev/null || true

echo
echo "==> Build a minimal rootfs containing only this binary:"
mkdir "$WORK/rootfs"
cp "$WORK/hello" "$WORK/rootfs/hello"
chmod +x "$WORK/rootfs/hello"

echo "==> Tar the rootfs:"
tar -C "$WORK/rootfs" -cf "$WORK/manual.tar" .
ls -lh "$WORK/manual.tar"
echo
echo "Tar entries:"
tar -tf "$WORK/manual.tar"

echo
echo "==> Import as an image, with --change to set ENTRYPOINT (Dockerfile-less):"
docker import --change 'ENTRYPOINT ["/hello"]' \
              "$WORK/manual.tar" manual-hello:v1

echo
echo "==> The new image:"
docker images manual-hello

echo
echo "==> Run it:"
docker run --rm manual-hello:v1

echo
echo "==> Inspect its config — looks just like any other image:"
docker inspect manual-hello:v1 --format '{{json .Config}}' | jq

echo
echo "==> Punchline: an image is a tar + a JSON config blob. That is all."
echo "==> Dockerfile + 'docker build' is a *convenience layer* on top."
echo "==> Tools like ko (Go), buildpacks, and bazel-rules-docker skip Dockerfile entirely."

docker rmi manual-hello:v1 >/dev/null
