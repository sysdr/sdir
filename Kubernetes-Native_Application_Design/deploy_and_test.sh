#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DEMO_DIR="${SCRIPT_DIR}/k8s-native-demo"

echo "🚀 Deploying and Testing Kubernetes-Native Application..."

cd "${K8S_DEMO_DIR}"

# Build images if they don't exist
if ! docker images | grep -q "k8s-native-app.*latest"; then
  echo "📦 Building app Docker image..."
  docker build -t k8s-native-app:latest ./app
fi

if ! docker images | grep -q "k8s-dashboard.*latest"; then
  echo "📦 Building dashboard Docker image (this may take a few minutes)..."
  docker build -t k8s-dashboard:latest ./dashboard || {
    echo "⚠️  Dashboard build failed, continuing with app services only..."
  }
fi

# Create/check kind cluster
if ! kind get clusters 2>/dev/null | grep -q k8s-native; then
  echo "🎪 Creating kind cluster..."
  kind create cluster --name k8s-native --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
EOF
fi

echo "📤 Loading images into kind..."
kind load docker-image k8s-native-app:latest --name k8s-native 2>/dev/null || true
if docker images | grep -q "k8s-dashboard.*latest"; then
  kind load docker-image k8s-dashboard:latest --name k8s-native 2>/dev/null || true
fi

echo "☸️  Deploying to Kubernetes..."
kubectl apply -f "${K8S_DEMO_DIR}/k8s/namespace.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/configmap.yaml"

# Create ConfigMaps
kubectl create configmap reporter-script \
  --from-file=reporter.js="${K8S_DEMO_DIR}/app/reporter.js" \
  -n k8s-native-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap aggregator-script \
  --from-file=aggregator.js="${K8S_DEMO_DIR}/app/aggregator.js" \
  -n k8s-native-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${K8S_DEMO_DIR}/k8s/deployment.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/aggregator-deployment.yaml"
if docker images | grep -q "k8s-dashboard.*latest"; then
  kubectl apply -f "${K8S_DEMO_DIR}/k8s/dashboard-deployment.yaml"
fi
kubectl apply -f "${K8S_DEMO_DIR}/k8s/service.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/hpa.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/pdb.yaml"

echo "⏳ Waiting for deployments (this may take a few minutes)..."
kubectl wait --for=condition=available --timeout=180s deployment/app-deployment -n k8s-native-demo || echo "⚠️  App deployment not ready yet"
kubectl wait --for=condition=available --timeout=180s deployment/aggregator-deployment -n k8s-native-demo || echo "⚠️  Aggregator deployment not ready yet"

echo ""
echo "📊 Checking pod status..."
kubectl get pods -n k8s-native-demo

echo ""
echo "🧪 Running tests..."
"${K8S_DEMO_DIR}/tests/test.sh" || echo "⚠️  Some tests may have failed"

echo ""
echo "✅ Deployment complete!"
echo "📊 Dashboard: http://localhost:30080 (if dashboard is deployed)"

