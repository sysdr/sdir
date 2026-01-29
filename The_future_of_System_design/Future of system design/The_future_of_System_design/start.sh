#!/bin/bash
cd "$(dirname "$0")" || exit 1
test -f docker-compose.yml || { echo "Run setup.sh first."; exit 1; }
docker-compose up -d
echo "Dashboard: http://localhost:8080"
