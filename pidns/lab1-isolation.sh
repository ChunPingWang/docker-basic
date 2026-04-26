#!/usr/bin/env bash
set -euo pipefail

NAME=pidns-lab1
docker rm -f $NAME >/dev/null 2>&1 || true

echo "==> Start a long-running container (sleep 60 will be PID 1 inside)"
docker run -d --rm --name $NAME ubuntu-pidns sleep 60 >/dev/null
sleep 0.3

echo
echo "==> View from INSIDE the container:"
docker exec $NAME ps -ef

echo
echo "==> View from the HOST:"
HOSTPID=$(docker inspect --format '{{.State.Pid}}' $NAME)
echo "Container's PID 1 inside  ==  PID $HOSTPID on the host"
echo
ps -p $HOSTPID -o pid,ppid,stat,cmd

echo
echo "==> Same process, two PIDs — that's PID namespace."
echo "==> The container can only see processes in its own namespace,"
echo "==> the host can see all of them with their host PIDs."

docker stop $NAME >/dev/null
