#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PROJ=lab2

cleanup() {
    docker compose -p $PROJ -f lab2-compose.yml down 2>/dev/null || true
    rm -f lab2-compose.yml
}
trap cleanup EXIT

cat > lab2-compose.yml <<'EOF'
services:
  web:
    image: nginx:alpine
  cache:
    image: redis:alpine
EOF

echo "==> Bring up stack:"
docker compose -p $PROJ -f lab2-compose.yml up -d 2>&1 | tail -3

echo
echo "==> Compose auto-creates a bridge network for the project:"
docker network ls --filter "name=${PROJ}_default"

echo
echo "==> Containers connected to it:"
docker network inspect ${PROJ}_default --format '{{range .Containers}}  {{.Name}} -> {{.IPv4Address}}{{"\n"}}{{end}}'

echo
echo "==> Service names are automatically resolvable inside the network."
echo "==> From 'web', look up 'cache' by name:"
docker compose -p $PROJ -f lab2-compose.yml exec -T web sh -c '
echo "[in web] nslookup-style via getent:"
getent hosts cache
echo
echo "[in web] HTTP-style ping (-c 2):"
ping -c 2 -W 1 cache 2>&1 | tail -3 || echo "(ping may need extra cap)"
echo
echo "[in web] use nc to talk to redis directly:"
echo -e "PING\r\nQUIT\r\n" | nc -w 1 cache 6379 || echo "(nc not available; ping above already proved DNS works)"
'

echo
echo "==> Punchline: compose creates a per-project bridge network with embedded DNS."
echo "==> Service-to-service comms use service names as hostnames — no IP juggling."
