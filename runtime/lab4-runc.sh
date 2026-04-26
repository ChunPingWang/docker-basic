#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "runc creates real namespaces and needs root (use sudo)." >&2
    exit 1
fi

WORK="$(mktemp -d -t runtime-lab4-XXXX)"
CNAME=runtime-lab4-c
cleanup() {
    runc delete -f $CNAME 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Build a real OCI bundle and run it with runc, no Docker."
echo

# Step 1: extract a rootfs from an Alpine container
echo "==> Step 1: extract a rootfs (use docker export for convenience):"
TEMP_C=runtime-lab4-export
docker rm -f $TEMP_C >/dev/null 2>&1 || true
docker run -d --name $TEMP_C alpine:3.19 sleep 60 >/dev/null
mkdir -p "$WORK/bundle/rootfs"
docker export $TEMP_C | tar -C "$WORK/bundle/rootfs" -xf -
docker rm -f $TEMP_C >/dev/null
echo "  rootfs size: $(du -sh "$WORK/bundle/rootfs" | cut -f1)"
echo "  $(ls "$WORK/bundle/rootfs" | head -10 | tr '\n' ' ')..."

# Step 2: generate the spec
echo
echo "==> Step 2: generate config.json:"
cd "$WORK/bundle"
runc spec
echo "  config.json size: $(wc -c < config.json) bytes"

# Step 3: customize args & terminal
echo
echo "==> Step 3: edit the spec to run /bin/echo and disable terminal:"
jq '.process.terminal = false |
    .process.args = ["/bin/sh", "-c", "echo hello from runc; echo my pid is $$; ls /etc | head -3"]' \
    config.json > config.tmp && mv config.tmp config.json

jq '.process | {terminal, args}' config.json

# Step 4: run with runc
echo
echo "==> Step 4: runc run $CNAME"
echo "------------------------------------------------------------"
runc run $CNAME
echo "------------------------------------------------------------"

echo
echo "==> Punchline: runc takes a bundle (rootfs + config.json) and turns it"
echo "==> into a running container by calling clone()/unshare() with the right"
echo "==> namespace flags, setting up cgroups, applying capabilities/seccomp,"
echo "==> and exec()ing your binary. That is ALL Docker / K8s does at the bottom."
