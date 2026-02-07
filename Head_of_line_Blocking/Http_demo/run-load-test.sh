#!/bin/bash
set -e

echo "📊 Running load test to populate dashboard metrics..."
for i in $(seq 0 19); do
  curl -s -o /dev/null "http://127.0.0.1:8443/chunk/$i" &
  curl -s -o /dev/null "http://127.0.0.1:8444/chunk/$i" &
done
wait
echo "✅ Load test complete. Dashboard metrics should now be updated."
