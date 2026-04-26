#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This lab manipulates kernel mounts and must run as root (use sudo)." >&2
    exit 1
fi

ROOT="${ROOT:-/tmp/storage-lab5}"

if mountpoint -q "$ROOT/merged" 2>/dev/null; then
    umount "$ROOT/merged"
fi
rm -rf "$ROOT"
mkdir -p "$ROOT"/{lower,upper,work,merged}

echo "==> Create a fake 'image layer' in lower/"
echo "from base image" > "$ROOT/lower/seed.txt"
echo "common config"   > "$ROOT/lower/config.txt"

echo "==> Initial layout:"
ls -R "$ROOT"

echo
echo "==> Mount overlayfs:  lower (read-only) + upper (writable) -> merged"
mount -t overlay overlay \
    -o lowerdir="$ROOT/lower",upperdir="$ROOT/upper",workdir="$ROOT/work" \
    "$ROOT/merged"

findmnt "$ROOT/merged"

echo
echo "==> merged sees lower's content:"
ls "$ROOT/merged"
cat "$ROOT/merged/seed.txt"

echo
echo "==> Modify a file via merged (Copy-on-Write into upper)"
echo "modified at runtime" > "$ROOT/merged/seed.txt"
echo "new file from container" > "$ROOT/merged/new.txt"

echo
echo "==> upper now holds the diff:"
ls "$ROOT/upper"
cat "$ROOT/upper/seed.txt"

echo
echo "==> lower is untouched (this is how multiple containers can share a base image):"
cat "$ROOT/lower/seed.txt"

echo
echo "==> merged shows the merged view (upper wins where both exist):"
cat "$ROOT/merged/seed.txt"

echo
echo "Cleanup:"
echo "  sudo umount $ROOT/merged && sudo rm -rf $ROOT"
