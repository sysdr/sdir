#!/bin/bash
BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE" || exit 1
echo "Stopping and removing all containers..."
docker-compose down -v --remove-orphans 2>/dev/null || true
docker rmi log-aggregation-demo_load-generator log_aggregation_at_scale_load-generator 2>/dev/null || true
echo "Removing generated files and folders (keeping setup.sh)..."
rm -rf loki promtail grafana load-generator frontend nginx elasticsearch scripts docker-compose.yml
echo "Cleanup complete."
