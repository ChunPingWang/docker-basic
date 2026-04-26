#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "runc needs root (use sudo)." >&2
    exit 1
fi

WORK="$(mktemp -d -t runtime-lab5-XXXX)"
CNAME=runtime-lab5-c
cleanup() {
    runc delete -f $CNAME 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Use the OCI spec to customize what the container can do."
echo "==> We start from a default spec and add: memory limit, dropped caps, env vars."
echo

# Build bundle
TEMP_C=runtime-lab5-export
docker rm -f $TEMP_C >/dev/null 2>&1 || true
docker run -d --name $TEMP_C alpine:3.19 sleep 60 >/dev/null
mkdir -p "$WORK/bundle/rootfs"
docker export $TEMP_C | tar -C "$WORK/bundle/rootfs" -xf - 2>/dev/null
docker rm -f $TEMP_C >/dev/null

cd "$WORK/bundle"
runc spec

# Customize:
#   - args: shell that prints all the things we set
#   - env: add a custom variable
#   - capabilities: drop everything except CAP_NET_BIND_SERVICE
#   - memory limit: 32MB
echo "==> Customizing config.json..."
jq '
.process.terminal = false |
.process.args = [
  "/bin/sh", "-c",
  "echo MY_VAR=$MY_VAR; echo memory.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo n/a); cat /proc/self/status | grep CapEff"
] |
.process.env += ["MY_VAR=hello-from-spec"] |
.process.capabilities.bounding   = ["CAP_NET_BIND_SERVICE"] |
.process.capabilities.effective  = ["CAP_NET_BIND_SERVICE"] |
.process.capabilities.permitted  = ["CAP_NET_BIND_SERVICE"] |
.linux.resources.memory = {limit: 33554432}
' config.json > config.tmp && mv config.tmp config.json

echo
echo "==> Selected sections of the modified config.json:"
jq '{args: .process.args, env: .process.env, caps: .process.capabilities.effective, memory: .linux.resources.memory}' config.json

echo
echo "==> Run it:"
echo "------------------------------------------------------------"
runc run $CNAME
echo "------------------------------------------------------------"

echo
echo "==> Notice in the output:"
echo "    MY_VAR     — environment variable we injected"
echo "    memory.max — 33554432 bytes (= 32MB), set via .linux.resources.memory"
echo "    CapEff     — only NET_BIND_SERVICE bit is set (1024 = bit 10)"
echo
echo "==> Every Docker / Compose / K8s flag eventually compiles down to a tweak"
echo "==> of fields in this same config.json. Reading the spec is reading the"
echo "==> definitive contract between orchestrators and runtimes."
