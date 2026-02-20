#!/bin/bash
# =============================================================================
# Immutable Infrastructure - Full cleanup
# Stops containers, removes unused Docker resources, and project artifacts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "════════════════════════════════════════"
echo "  Stopping containers"
echo "════════════════════════════════════════"
# Stop demo stack if present
if [ -d "immutable-infra-demo" ]; then
  (cd immutable-infra-demo && docker compose down -v 2>/dev/null) || true
fi
docker stop $(docker ps -aq) 2>/dev/null || true
echo "  Containers stopped."

echo ""
echo "════════════════════════════════════════"
echo "  Removing unused Docker resources"
echo "════════════════════════════════════════"
docker system prune -af --volumes 2>/dev/null || true
echo "  Unused containers, images, volumes, and networks removed."

echo ""
echo "════════════════════════════════════════"
echo "  Removing project artifacts"
echo "════════════════════════════════════════"
find "$SCRIPT_DIR" -type d \( -name "node_modules" -o -name "venv" -o -name ".venv" -o -name ".pytest_cache" -o -name "__pycache__" \) 2>/dev/null | while read -r d; do echo "  Removing: $d"; rm -rf "$d"; done
find "$SCRIPT_DIR" -name "*.pyc" 2>/dev/null | while read -r f; do echo "  Removing: $f"; rm -f "$f"; done
find "$SCRIPT_DIR" -maxdepth 4 -type d -name "istio-*" 2>/dev/null | while read -r d; do echo "  Removing (Istio): $d"; rm -rf "$d"; done
echo "  Artifact cleanup done."
echo ""
echo "════════════════════════════════════════"
echo "  ✓ Cleanup complete"
echo "════════════════════════════════════════"
