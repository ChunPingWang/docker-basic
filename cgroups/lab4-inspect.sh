#!/usr/bin/env bash
set -euo pipefail

NAME=cgroup-lab4
docker rm -f $NAME >/dev/null 2>&1 || true

echo "==> Start a container with all three limits at once:"
echo "    --memory=64m  --cpus=0.5  --pids-limit=50"
echo

docker container run -d --rm --name $NAME \
    --memory=64m --cpus=0.5 --pids-limit=50 \
    ubuntu-cgroups sleep 60 >/dev/null

PID=$(docker inspect --format '{{.State.Pid}}' $NAME)
echo "==> Container's main PID on the host: $PID"

echo
echo "==> /proc/$PID/cgroup tells us where the kernel put it:"
cat /proc/$PID/cgroup

REL=$(awk -F: 'NR==1{print $3}' /proc/$PID/cgroup)
CG="/sys/fs/cgroup$REL"
echo
echo "==> Resolved cgroupfs path:"
echo "    $CG"

if [[ -d $CG ]]; then
    echo
    echo "==> Selected files Docker actually wrote into this cgroup:"
    for f in memory.max memory.current cpu.max pids.max pids.current cgroup.procs; do
        if [[ -f $CG/$f ]]; then
            value="$(tr '\n' ' ' < $CG/$f)"
            printf "    %-22s %s\n" "$f" "$value"
        fi
    done
fi

echo
echo "==> Punchline: 'docker run --memory=64m' = the kernel writes 64M into"
echo "    that cgroup's memory.max. Docker is just a friendly wrapper."

docker stop $NAME >/dev/null 2>&1 || true
