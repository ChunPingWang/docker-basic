#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Use compose to bring up a 2-service stack (nginx + redis)"
echo "==> The compose file is in this directory: lab1-compose.yml"
echo

cat > lab1-compose.yml <<'EOF'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
  cache:
    image: redis:alpine
EOF

echo "==> Compose file:"
cat lab1-compose.yml
echo

echo "==> Bring it up in background:"
docker compose -p lab1 -f lab1-compose.yml up -d 2>&1 | tail -10

echo
echo "==> docker compose ps:"
docker compose -p lab1 -f lab1-compose.yml ps

echo
echo "==> Hit nginx from the host:"
sleep 1
curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8080/

echo
echo "==> Tear down:"
docker compose -p lab1 -f lab1-compose.yml down 2>&1 | tail -5

rm -f lab1-compose.yml
