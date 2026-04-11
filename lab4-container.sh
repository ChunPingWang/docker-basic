#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target-container-id-or-name>"
    echo "Hint: start a bridge-mode container first via ./lab3-bridge.sh, then pass its ID here."
    exit 1
fi

target="$1"
docker container run -it --rm --network="container:${target}" ubuntu-network
