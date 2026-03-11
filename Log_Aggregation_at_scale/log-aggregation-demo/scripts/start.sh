#!/bin/bash
BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE" || exit 1
echo "Starting Log Aggregation Demo stack from $BASE"
docker-compose up -d
echo "Wait ~30s for Loki/ES/Grafana to be ready. Dashboard: http://localhost:8214"
