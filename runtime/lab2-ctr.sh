#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ctr talks to /run/containerd/containerd.sock and needs root (use sudo)." >&2
    exit 1
fi

echo "==> Skip Docker — talk to containerd directly with ctr."
echo "==> ctr is the low-level CLI for containerd, similar to how docker is for dockerd."
echo

NS=runtime-lab2
echo "==> Pull alpine into a new containerd namespace ($NS):"
ctr -n $NS images pull docker.io/library/alpine:3.19 2>&1 | tail -3

echo
echo "==> List images in this namespace:"
ctr -n $NS images list

echo
echo "==> Compare with Docker's containerd namespace ('moby'):"
ctr -n moby images list 2>/dev/null | head -5 || echo "(no moby ns or empty)"

echo
echo "==> Run a one-shot container directly via containerd:"
ctr -n $NS run --rm --tty=false docker.io/library/alpine:3.19 mytest \
    /bin/sh -c 'echo "hello from $(hostname) running under ctr"; sleep 0.5'

echo
echo "==> Cleanup:"
ctr -n $NS images rm docker.io/library/alpine:3.19 >/dev/null 2>&1 || true
# Snapshots and content are kept (referenced by the image until GC). Trigger GC:
ctr -n $NS content prune references >/dev/null 2>&1 || true
for snap in $(ctr -n $NS snapshots list 2>/dev/null | awk 'NR>1 {print $1}'); do
    ctr -n $NS snapshots rm "$snap" >/dev/null 2>&1 || true
done
ctr -n $NS namespaces remove $NS >/dev/null 2>&1 || true
echo "  done."

echo
echo "==> Punchline: containerd has its own CLI (ctr) and its own image store,"
echo "==> independent of dockerd. Docker, K8s, podman all sit on top of"
echo "==> containerd (or another OCI-compatible runtime)."
