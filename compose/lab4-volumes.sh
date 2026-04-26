#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PROJ=lab4
cleanup() {
    docker compose -p $PROJ -f lab4-compose.yml down -v 2>/dev/null || true
    rm -f lab4-compose.yml
}
trap cleanup EXIT

cat > lab4-compose.yml <<'EOF'
services:
  cache:
    image: redis:alpine
    environment:
      - REDIS_PASSWORD_HINT=set-via-env
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - cache-data:/data
    restart: unless-stopped

volumes:
  cache-data:
EOF

echo "==> Compose file with named volume + env vars + restart policy:"
cat lab4-compose.yml

echo
echo "==> First run: write data into redis"
docker compose -p $PROJ -f lab4-compose.yml up -d 2>&1 | tail -3
sleep 1
docker compose -p $PROJ -f lab4-compose.yml exec -T cache redis-cli SET hello "saved at $(date -Iseconds)"
docker compose -p $PROJ -f lab4-compose.yml exec -T cache redis-cli GET hello

echo
echo "==> Restart the container (data should survive — it's in a volume, not the container):"
docker compose -p $PROJ -f lab4-compose.yml restart cache 2>&1 | tail -3
sleep 1
echo "==> Same key after restart:"
docker compose -p $PROJ -f lab4-compose.yml exec -T cache redis-cli GET hello

echo
echo "==> Volumes that compose created (named after project + service):"
docker volume ls | grep "${PROJ}_"

echo
echo "==> Container env vars set from the compose file:"
docker compose -p $PROJ -f lab4-compose.yml exec -T cache env | grep -E '^REDIS_'

echo
echo "==> Tear down with -v to also delete volumes:"
docker compose -p $PROJ -f lab4-compose.yml down -v 2>&1 | tail -3

echo
echo "==> Punchline: same primitives as 'docker run -v ... -e ... --restart=...',"
echo "==> compose just gives you a YAML to declare them centrally + tear down all at once."
