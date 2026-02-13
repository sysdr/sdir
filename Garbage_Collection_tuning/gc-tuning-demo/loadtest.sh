#!/bin/bash
# Quick load test using curl — fires concurrent requests
LOAD="${1:-medium}"
CONCURRENCY="${2:-10}"
DURATION="${3:-30}"

echo "Load test: load=$LOAD, concurrency=$CONCURRENCY, duration=${DURATION}s"
END=$((SECONDS + DURATION))
COUNT=0

while [ $SECONDS -lt $END ]; do
  for i in $(seq 1 $CONCURRENCY); do
    curl -s "http://localhost:8080/process?load=$LOAD" > /dev/null &
    curl -s "http://localhost:8081/process?load=$LOAD" > /dev/null &
  done
  wait
  COUNT=$((COUNT + CONCURRENCY * 2))
  echo "Sent $COUNT requests..."
  sleep 0.2
done

echo ""
echo "=== Final Metrics ==="
echo "--- Java ---"
curl -s http://localhost:8080/metrics | python3 -m json.tool 2>/dev/null || \
  curl -s http://localhost:8080/metrics

echo ""
echo "--- Go ---"
curl -s http://localhost:8081/metrics | python3 -m json.tool 2>/dev/null || \
  curl -s http://localhost:8081/metrics
