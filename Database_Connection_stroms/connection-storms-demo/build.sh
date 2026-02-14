#!/bin/bash
# Database Connection Storms Demo - Build script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Building Database Connection Storms Demo"
echo "======================================"

cd "$SCRIPT_DIR"

echo ""
echo "🐳 Building Docker images..."
docker compose build backend frontend

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo ""
    echo "To start services, run:"
    echo "  cd $SCRIPT_DIR && docker compose up -d postgres pgbouncer backend frontend"
    echo ""
else
    echo ""
    echo "❌ Build failed. Check the errors above."
    exit 1
fi
