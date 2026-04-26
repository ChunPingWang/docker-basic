#!/usr/bin/env bash
set -euo pipefail

NAME=cgroup-lab2
docker rm -f $NAME >/dev/null 2>&1 || true

echo "==> Start a container with --cpus=0.5 burning 1 CPU core."
echo "==> Without limit it would peg one core to 100%; we expect ~50%."
echo

docker container run -d --rm --name $NAME --cpus=0.5 ubuntu-cgroups \
    stress-ng --cpu 1 --timeout 12s >/dev/null

echo "==> Let it ramp up..."
sleep 3

echo "==> docker stats snapshot:"
docker stats --no-stream --format \
    "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $NAME

echo
echo "==> What the container's cgroup actually says:"
docker exec $NAME cat /sys/fs/cgroup/cpu.max
echo "                         ^ quota   ^ period   (50000/100000 = 0.5 CPU)"

echo
echo "==> Wait for stress-ng to finish..."
docker wait $NAME >/dev/null 2>&1 || true
