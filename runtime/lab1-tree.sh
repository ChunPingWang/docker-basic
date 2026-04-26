#!/usr/bin/env bash
set -euo pipefail

NAME=runtime-lab1
docker rm -f $NAME >/dev/null 2>&1 || true

echo "==> Start a container, then walk the process-tree on the host"
echo "==> from the container's PID 1 up to PID 1 of the host."
echo

docker run -d --rm --name $NAME ubuntu:22.04 sleep 60 >/dev/null
sleep 0.5

PID=$(docker inspect --format '{{.State.Pid}}' $NAME)
echo "==> Container's PID 1 on host = $PID"
echo
echo "==> Walking up the parent chain:"
P=$PID
while [[ "$P" != "0" && "$P" != "1" ]]; do
    line=$(ps -o pid,ppid,comm,cmd -p $P --no-headers 2>/dev/null || true)
    if [[ -z "$line" ]]; then
        break
    fi
    echo "  $line"
    P=$(ps -o ppid= -p $P 2>/dev/null | tr -d ' ' || echo 0)
done

echo
echo "==> Typical chain you should see:"
echo "    sleep 60                       <- your app, container's PID 1"
echo "    containerd-shim-runc-v2        <- per-container shim, parent of your app"
echo "    systemd                        <- shim is a systemd-managed scope"
echo
echo "==> NOT visible directly in the chain (because shim is reparented):"
echo "    runc:                          <- forked, exec()d into your app, then exited"
echo "    containerd:                    <- spawned the shim and walked away"
echo "    dockerd:                       <- talks to containerd over gRPC"
echo
echo "==> Architecture:"
echo "    docker CLI -> dockerd -> containerd -> containerd-shim -> runc -> your app"
echo "                  (HTTP)     (gRPC)        (per-container)    (one-shot)"

docker stop $NAME >/dev/null
