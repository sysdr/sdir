#!/bin/bash
echo "Testing load distribution across the hierarchy..."
echo "=================================================="

for i in {1..12}; do
  echo "Request $i:"
  curl -s http://localhost:8000/ | jq -r '"\(.loadBalancer) -> \(.server)"'
  sleep 0.5
done

echo ""
echo "Testing L7 health endpoints directly:"
docker exec lb-scaling-demo-l7-balancer-1-1 curl -s http://localhost:8080/health
docker exec lb-scaling-demo-l7-balancer-2-1 curl -s http://localhost:8080/health
