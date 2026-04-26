#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PROJ=lab3
cleanup() {
    docker compose -p $PROJ -f lab3-compose.yml down 2>/dev/null || true
    rm -f lab3-compose.yml
}
trap cleanup EXIT

cat > lab3-compose.yml <<'EOF'
services:
  cache:
    image: redis:alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 1s
      timeout: 3s
      retries: 5

  web:
    image: nginx:alpine
    depends_on:
      cache:
        condition: service_healthy
    command: ["sh", "-c", "echo 'web starting'; nginx -g 'daemon off;'"]
EOF

echo "==> Compose file (with healthcheck on cache + service_healthy on web):"
cat lab3-compose.yml

echo
echo "==> Bring up. Web should NOT start until redis is healthy."
echo "==> Watch the order of events in --wait output:"
START=$(date +%s)
docker compose -p $PROJ -f lab3-compose.yml up -d --wait 2>&1
END=$(date +%s)
echo "==> Total time to 'all healthy': $((END - START))s"

echo
echo "==> docker compose ps with health column:"
docker compose -p $PROJ -f lab3-compose.yml ps

echo
echo "==> Punchline:"
echo "==>   - depends_on (without condition) only orders START, doesn't wait for ready."
echo "==>   - depends_on + condition: service_healthy waits for healthcheck to pass."
echo "==>   - depends_on + condition: service_completed_successfully = wait for one-shot job to finish."
echo "==> healthcheck in compose just calls into docker's HEALTHCHECK feature; the"
echo "==> CMD inside the container determines liveness."
