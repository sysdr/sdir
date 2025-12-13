#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DEMO_DIR="${SCRIPT_DIR}/k8s-native-demo"

# Add local bin to PATH if kind is installed locally
if [ -f "${SCRIPT_DIR}/bin/kind" ]; then
  export PATH="${SCRIPT_DIR}/bin:${PATH}"
fi

echo "🚀 Starting Kubernetes-Native Application Demo..."
echo "Working directory: ${K8S_DEMO_DIR}"

cd "${K8S_DEMO_DIR}"

# Check if Docker images exist
if ! docker images | grep -q "k8s-native-app.*latest"; then
  echo "📦 Building Docker images..."
  docker build -t k8s-native-app:latest ./app
else
  echo "✅ Docker image k8s-native-app:latest already exists"
fi

if ! docker images | grep -q "k8s-dashboard.*latest"; then
  echo "📦 Building dashboard Docker image..."
  docker build -t k8s-dashboard:latest ./dashboard
else
  echo "✅ Docker image k8s-dashboard:latest already exists"
fi

# Check if kind cluster exists
if kind get clusters 2>/dev/null | grep -q k8s-native; then
  echo "✅ Cluster k8s-native already exists, using it"
else

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
kind load docker-image k8s-native-app:latest --name k8s-native
kind load docker-image k8s-dashboard:latest --name k8s-native

echo "☸️  Deploying to Kubernetes..."
kubectl apply -f "${K8S_DEMO_DIR}/k8s/namespace.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/configmap.yaml"

# Create reporter script ConfigMap (check if exists first)
if ! kubectl get configmap reporter-script -n k8s-native-demo &>/dev/null; then
  kubectl create configmap reporter-script \
    --from-file=reporter.js="${K8S_DEMO_DIR}/app/reporter.js" \
    -n k8s-native-demo
else
  echo "✅ ConfigMap reporter-script already exists"
fi

# Create aggregator script ConfigMap (check if exists first)
if ! kubectl get configmap aggregator-script -n k8s-native-demo &>/dev/null; then
  kubectl create configmap aggregator-script \
    --from-file=aggregator.js="${K8S_DEMO_DIR}/app/aggregator.js" \
    -n k8s-native-demo
else
  echo "✅ ConfigMap aggregator-script already exists"
fi

kubectl apply -f "${K8S_DEMO_DIR}/k8s/deployment.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/aggregator-deployment.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/dashboard-deployment.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/service.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/hpa.yaml"
kubectl apply -f "${K8S_DEMO_DIR}/k8s/pdb.yaml"

echo "⏳ Waiting for deployments..."
kubectl wait --for=condition=available --timeout=120s deployment/app-deployment -n k8s-native-demo || true
kubectl wait --for=condition=available --timeout=120s deployment/aggregator-deployment -n k8s-native-demo || true
kubectl wait --for=condition=available --timeout=120s deployment/dashboard-deployment -n k8s-native-demo || true

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Dashboard: http://localhost:30080"
echo ""
echo "🔍 Useful commands:"
echo "  kubectl get pods -n k8s-native-demo"
echo "  kubectl logs -f <pod-name> -n k8s-native-demo"
echo "  kubectl describe hpa app-hpa -n k8s-native-demo"
echo "  ${K8S_DEMO_DIR}/tests/test.sh"

