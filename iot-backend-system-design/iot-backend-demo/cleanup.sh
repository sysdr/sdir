#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧹 Cleaning up IoT Backend Demo..."

docker compose down -v --remove-orphans 2>/dev/null || true
cd ..
rm -rf "$PROJECT_DIR"

echo "✅ Cleanup complete!"
