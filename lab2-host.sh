#!/usr/bin/env bash
set -euo pipefail
docker container run -it --rm --network=host ubuntu-network
