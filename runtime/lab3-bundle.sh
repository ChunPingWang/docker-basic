#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t runtime-lab3-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> An OCI bundle is just a directory with two things:"
echo "    rootfs/        — the filesystem the container will see as its root"
echo "    config.json    — JSON describing how to run it (cmd, env, namespaces, caps...)"
echo

echo "==> Make a bundle skeleton:"
mkdir -p "$WORK/bundle/rootfs"
cd "$WORK/bundle"

echo "==> Use 'runc spec' to generate a default config.json:"
runc spec
echo
echo "==> Bundle directory:"
ls -la "$WORK/bundle"

echo
echo "==> Top-level keys of config.json:"
jq 'keys' config.json

echo
echo "==> The .process section (what runs):"
jq '.process' config.json

echo
echo "==> The .linux.namespaces section (which namespaces to create):"
jq '.linux.namespaces' config.json

echo
echo "==> The .mounts section (mounts inside rootfs):"
jq '.mounts' config.json | head -20

echo
echo "==> Punchline: this JSON is the OCI Runtime Spec format. Any compatible"
echo "==> runtime (runc, crun, kata-runtime, gVisor) takes the same input."
echo "==> Lab 4 actually runs this bundle."
