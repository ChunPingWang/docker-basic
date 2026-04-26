#!/usr/bin/env bash
set -euo pipefail

NET=lab5-net
VOL=lab5-cache-data
WEB=lab5-web
CACHE=lab5-cache

cleanup() {
    docker rm -f $WEB $CACHE >/dev/null 2>&1 || true
    docker network rm $NET >/dev/null 2>&1 || true
    docker volume rm $VOL >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup   # in case there's leftover from a previous run

echo "==> Reproduce Lab 4's compose stack with NOTHING but plain docker commands."
echo "==> This shows compose is a YAML wrapper around the same primitives."
echo

echo "==> 1. Create the network compose would have created:"
docker network create $NET >/dev/null
echo "    docker network create $NET"

echo
echo "==> 2. Create the named volume:"
docker volume create $VOL >/dev/null
echo "    docker volume create $VOL"

echo
echo "==> 3. Run cache:"
echo "    docker run -d --name $CACHE --network $NET --network-alias cache \\"
echo "        -v $VOL:/data -e REDIS_PASSWORD_HINT=set-via-env \\"
echo "        --restart unless-stopped redis:alpine \\"
echo "        redis-server --appendonly yes"
docker run -d --name $CACHE --network $NET --network-alias cache \
    -v $VOL:/data -e REDIS_PASSWORD_HINT=set-via-env \
    --restart unless-stopped redis:alpine \
    redis-server --appendonly yes >/dev/null

echo
echo "==> 4. Run web:"
echo "    docker run -d --name $WEB --network $NET --network-alias web \\"
echo "        -p 8080:80 nginx:alpine"
docker run -d --name $WEB --network $NET --network-alias web \
    -p 8080:80 nginx:alpine >/dev/null

sleep 1
echo
echo "==> 5. Verify (same as Lab 1/2):"
echo "  - HTTP from host:"
curl -s -o /dev/null -w "    HTTP %{http_code}\n" http://localhost:8080/
echo "  - DNS web -> cache works:"
docker exec $WEB getent hosts cache
echo "  - redis ping via nc from web:"
docker exec $WEB sh -c 'echo -e "PING\r\nQUIT\r\n" | nc -w 1 cache 6379'

echo
echo "==> Punchline: the 'magic' of compose is six docker commands stitched together."
echo "==> What compose adds:"
echo "      - YAML > 6 commands (declarative > imperative)"
echo "      - automatic naming (compose-prefix conventions)"
echo "      - tear-down (compose down ≈ rm + network rm + volume rm)"
echo "      - depends_on / healthcheck orchestration"
echo "      - profiles, secrets, override files for env-specific tweaks"
echo "==> But the runtime model is identical."
