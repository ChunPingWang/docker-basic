#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker build -f Dockerfile-ubuntu-caps -t ubuntu-caps .
