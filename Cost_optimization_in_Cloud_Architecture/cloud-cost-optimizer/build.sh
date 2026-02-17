#!/bin/bash
# Build the cloud-cost-optimizer Docker image.
# Run from cloud-cost-optimizer: ./build.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f Dockerfile ]]; then
  echo "Error: Dockerfile not found. Run setup.sh from repo root first."
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "Error: Docker not found."
  exit 1
fi

docker build -t cloud-cost-optimizer .
echo "OK: Image built: cloud-cost-optimizer"
