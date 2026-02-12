#!/bin/bash

set -e

cd "$(dirname "$0")"

echo "🧪 Running Load Shedding tests..."
echo ""

# Run inside container if load-shedding is up; otherwise run locally (server must be on localhost:3000)
CID=$(docker-compose ps -q load-shedding 2>/dev/null)
if [ -n "$CID" ] && docker inspect -f '{{.State.Running}}' "$CID" 2>/dev/null | grep -q true; then
  docker-compose exec -T load-shedding node tests/load-shedding.test.js
else
  echo "Running tests against localhost:3000 (start with ./start.sh if needed)"
  node tests/load-shedding.test.js
fi

echo ""
echo "✅ All tests passed!"
