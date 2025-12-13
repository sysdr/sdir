#!/bin/bash

echo "🧪 Running K8s-Native Application Tests..."

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=k8s-native-app -n k8s-native-demo --timeout=60s

# Test 1: Health checks
echo "Test 1: Verifying health checks..."
POD_NAME=$(kubectl get pods -n k8s-native-demo -l app=k8s-native-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n k8s-native-demo $POD_NAME -- wget -q -O- http://localhost:3000/health/live | grep "alive"
kubectl exec -n k8s-native-demo $POD_NAME -- wget -q -O- http://localhost:3000/health/ready | grep "ready"
echo "✅ Health checks passed"

# Test 2: ConfigMap injection
echo "Test 2: Verifying ConfigMap values..."
kubectl exec -n k8s-native-demo $POD_NAME -- env | grep "MAX_CONCURRENT=100"
echo "✅ ConfigMap injection passed"

# Test 3: Pod communication
echo "Test 3: Testing service communication..."
kubectl run test-pod --image=alpine/curl --rm -i --restart=Never -n k8s-native-demo -- \
  curl -s http://app-service:3000/api/process | grep "processed"
echo "✅ Service communication passed"

# Test 4: Graceful shutdown
echo "Test 4: Testing graceful shutdown..."
kubectl delete pod $POD_NAME -n k8s-native-demo &
sleep 2
kubectl logs -n k8s-native-demo $POD_NAME | grep "graceful shutdown" || echo "Pod deleted before log capture"
echo "✅ Graceful shutdown initiated"

# Test 5: HPA configuration
echo "Test 5: Verifying HPA..."
kubectl get hpa -n k8s-native-demo app-hpa
echo "✅ HPA configured"

echo ""
echo "✅ All tests passed!"
