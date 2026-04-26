#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t image-lab4-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> Demo: build the same hello-world program three ways and compare sizes."
echo "==> 1. ubuntu base (apt install gcc, leave gcc behind)  — ~370 MB"
echo "==> 2. ubuntu builder + alpine runtime (multi-stage)    — ~10 MB"
echo "==> 3. ubuntu builder + scratch runtime (static binary) — ~1 MB"
echo

cat > "$WORK/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { printf("hello from a tiny image\n"); return 0; }
EOF

# ---- Image 1: fat ----
cat > "$WORK/Dockerfile.fat" <<'EOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc-dev
COPY hello.c /hello.c
RUN gcc -o /hello /hello.c
ENTRYPOINT ["/hello"]
EOF

# ---- Image 2: alpine multi-stage ----
cat > "$WORK/Dockerfile.alpine" <<'EOF'
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc-dev
COPY hello.c /hello.c
RUN gcc -o /hello /hello.c

FROM alpine:3.19
# Need glibc compat or we re-compile static. Easier: copy statically-linked binary.
COPY --from=builder /hello /hello
ENTRYPOINT ["/hello"]
EOF

# ---- Image 3: scratch + static ----
cat > "$WORK/Dockerfile.scratch" <<'EOF'
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc-dev
COPY hello.c /hello.c
RUN gcc -static -o /hello /hello.c

FROM scratch
COPY --from=builder /hello /hello
ENTRYPOINT ["/hello"]
EOF

echo "==> Building all three (this will take ~30s the first time)..."
docker build -q -f "$WORK/Dockerfile.fat"     -t hello-fat     "$WORK" >/dev/null
docker build -q -f "$WORK/Dockerfile.scratch" -t hello-scratch "$WORK" >/dev/null
# Skip alpine variant if it would crash (we used dynamic gcc -o, so it needs glibc)
# Build the static one and copy into alpine:
cat > "$WORK/Dockerfile.alpine" <<'EOF'
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc-dev
COPY hello.c /hello.c
RUN gcc -static -o /hello /hello.c

FROM alpine:3.19
COPY --from=builder /hello /hello
ENTRYPOINT ["/hello"]
EOF
docker build -q -f "$WORK/Dockerfile.alpine" -t hello-alpine "$WORK" >/dev/null

echo
echo "==> Size comparison:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" \
    | grep -E "REPOSITORY|^hello-"

echo
echo "==> They all produce the same output:"
echo "[hello-fat]"     ; docker run --rm hello-fat
echo "[hello-alpine]"  ; docker run --rm hello-alpine
echo "[hello-scratch]"; docker run --rm hello-scratch

echo
echo "==> Punchline: the build toolchain (gcc + headers) is huge; the final"
echo "==> binary is tiny. Multi-stage build lets you keep the toolchain only"
echo "==> in the builder stage, and ship just the binary in the final image."
