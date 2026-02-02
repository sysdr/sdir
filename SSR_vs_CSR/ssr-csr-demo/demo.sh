#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🎯 SSR vs CSR Performance Demo - Triggering traffic to populate metrics..."
echo ""

# Wait for service to be healthy
echo "Waiting for service to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:3000/api/metrics > /dev/null 2>&1; then
    echo "✅ Service is ready!"
    break
  fi
  sleep 1
done

# Trigger demo traffic - hit SSR and CSR endpoints to populate metrics
echo ""
echo "📊 Triggering demo traffic (SSR and CSR requests)..."
for i in 1 2 3 4 5; do
  curl -s -o /dev/null http://localhost:3000/api/ssr
  echo "   SSR request $i completed"
  sleep 0.5
done
for i in 1 2 3 4 5; do
  curl -s -o /dev/null http://localhost:3000/api/csr
  echo "   CSR request $i completed"
  sleep 0.5
done

echo ""
echo "✅ Demo traffic complete! Metrics should now be populated."
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔵 SSR Demo: http://localhost:3000/api/ssr"
echo "🔴 CSR Demo: http://localhost:3000/api/csr"
echo ""
echo "Open the dashboard to see updated metrics (non-zero values)."
echo ""

# Open browser if available
if command -v xdg-open > /dev/null; then
  xdg-open http://localhost:3000
elif command -v open > /dev/null; then
  open http://localhost:3000
fi
