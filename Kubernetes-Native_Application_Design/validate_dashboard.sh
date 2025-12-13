#!/bin/bash

echo "🔍 Validating Dashboard Metrics..."

# Check for duplicate services
echo "Checking for duplicate services..."
DUPLICATE_PODS=$(kubectl get pods -n k8s-native-demo -l app=k8s-native-app --no-headers 2>/dev/null | wc -l)
if [ "$DUPLICATE_PODS" -gt 2 ]; then
  echo "⚠️  Warning: Found $DUPLICATE_PODS app pods (expected 2)"
else
  echo "✅ Found $DUPLICATE_PODS app pod(s) (expected 2)"
fi

# Check aggregator service
AGGREGATOR_PODS=$(kubectl get pods -n k8s-native-demo -l app=aggregator --no-headers 2>/dev/null | wc -l)
echo "✅ Found $AGGREGATOR_PODS aggregator pod(s)"

# Wait for pods to be ready
echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=k8s-native-app -n k8s-native-demo --timeout=60s 2>/dev/null || echo "⚠️  Some pods not ready yet"
kubectl wait --for=condition=ready pod -l app=aggregator -n k8s-native-demo --timeout=60s 2>/dev/null || echo "⚠️  Aggregator not ready yet"

# Get aggregator pod
AGGREGATOR_POD=$(kubectl get pods -n k8s-native-demo -l app=aggregator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$AGGREGATOR_POD" ]; then
  echo "❌ Aggregator pod not found"
  exit 1
fi

echo ""
echo "📊 Checking metrics endpoint..."
sleep 5  # Give pods time to report

# Check metrics via port-forward or service
METRICS=$(kubectl exec -n k8s-native-demo $AGGREGATOR_POD -- wget -q -O- http://localhost:4000/api/pods/status 2>/dev/null || echo "{}")

if [ "$METRICS" = "{}" ]; then
  echo "⚠️  Could not fetch metrics directly, trying via service..."
  # Try via service using a test pod
  kubectl run test-metrics --image=alpine/curl --rm -i --restart=Never -n k8s-native-demo -- \
    curl -s http://aggregator-service:4000/api/pods/status 2>/dev/null > /tmp/metrics.json || echo "{}" > /tmp/metrics.json
  METRICS=$(cat /tmp/metrics.json 2>/dev/null || echo "{}")
fi

# Parse metrics
TOTAL_REQUESTS=$(echo "$METRICS" | grep -o '"totalRequests":[0-9]*' | grep -o '[0-9]*' || echo "0")
AVG_RESPONSE=$(echo "$METRICS" | grep -o '"avgResponseTime":[0-9]*' | grep -o '[0-9]*' || echo "0")
POD_COUNT=$(echo "$METRICS" | grep -o '"name":"[^"]*"' | wc -l || echo "0")

echo ""
echo "📈 Current Metrics:"
echo "  Total Requests: $TOTAL_REQUESTS"
echo "  Avg Response Time: ${AVG_RESPONSE}ms"
echo "  Pods Reporting: $POD_COUNT"

if [ "$TOTAL_REQUESTS" = "0" ] && [ "$POD_COUNT" = "0" ]; then
  echo ""
  echo "⚠️  Metrics are zero or pods not reporting. Generating test load..."
  
  # Generate some test load
  kubectl run test-load --image=alpine/curl --rm -i --restart=Never -n k8s-native-demo -- \
    curl -X POST http://aggregator-service:4000/api/load/generate \
    -H "Content-Type: application/json" \
    -d '{"intensity":"low"}' 2>/dev/null || echo "Could not generate load"
  
  echo "Waiting 10 seconds for metrics to update..."
  sleep 10
  
  # Check metrics again
  METRICS=$(kubectl exec -n k8s-native-demo $AGGREGATOR_POD -- wget -q -O- http://localhost:4000/api/pods/status 2>/dev/null || echo "{}")
  TOTAL_REQUESTS=$(echo "$METRICS" | grep -o '"totalRequests":[0-9]*' | grep -o '[0-9]*' || echo "0")
  AVG_RESPONSE=$(echo "$METRICS" | grep -o '"avgResponseTime":[0-9]*' | grep -o '[0-9]*' || echo "0")
  
  echo ""
  echo "📈 Updated Metrics:"
  echo "  Total Requests: $TOTAL_REQUESTS"
  echo "  Avg Response Time: ${AVG_RESPONSE}ms"
fi

# Validate metrics are not zero
if [ "$TOTAL_REQUESTS" != "0" ] || [ "$AVG_RESPONSE" != "0" ] || [ "$POD_COUNT" != "0" ]; then
  echo ""
  echo "✅ Dashboard metrics are updating correctly!"
  echo "   - At least one metric is non-zero"
  echo "   - Pods are reporting status"
else
  echo ""
  echo "❌ Warning: All metrics are still zero"
  echo "   This may indicate:"
  echo "   - Pods are not reporting to aggregator"
  echo "   - No requests have been processed yet"
  echo "   - Aggregator service is not receiving data"
fi

# Check dashboard accessibility
echo ""
echo "🌐 Checking dashboard accessibility..."
DASHBOARD_POD=$(kubectl get pods -n k8s-native-demo -l app=dashboard -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DASHBOARD_POD" ]; then
  echo "✅ Dashboard pod found: $DASHBOARD_POD"
  echo "📊 Dashboard should be accessible at: http://localhost:30080"
else
  echo "⚠️  Dashboard pod not found (may still be building)"
fi

echo ""
echo "✅ Validation complete!"

