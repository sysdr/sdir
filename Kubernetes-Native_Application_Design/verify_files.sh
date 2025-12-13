#!/bin/bash

echo "🔍 Verifying generated files..."

BASE_DIR="k8s-native-demo"
MISSING_FILES=0

# Expected files
declare -a FILES=(
  "$BASE_DIR/app/package.json"
  "$BASE_DIR/app/server.js"
  "$BASE_DIR/app/Dockerfile"
  "$BASE_DIR/app/aggregator.js"
  "$BASE_DIR/app/reporter.js"
  "$BASE_DIR/dashboard/package.json"
  "$BASE_DIR/dashboard/public/index.html"
  "$BASE_DIR/dashboard/src/index.js"
  "$BASE_DIR/dashboard/src/App.js"
  "$BASE_DIR/dashboard/src/App.css"
  "$BASE_DIR/dashboard/Dockerfile"
  "$BASE_DIR/dashboard/nginx.conf"
  "$BASE_DIR/k8s/namespace.yaml"
  "$BASE_DIR/k8s/configmap.yaml"
  "$BASE_DIR/k8s/deployment.yaml"
  "$BASE_DIR/k8s/aggregator-deployment.yaml"
  "$BASE_DIR/k8s/service.yaml"
  "$BASE_DIR/k8s/dashboard-deployment.yaml"
  "$BASE_DIR/k8s/hpa.yaml"
  "$BASE_DIR/k8s/pdb.yaml"
  "$BASE_DIR/tests/test.sh"
  "cleanup.sh"
)

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "✅ $file"
  else
    echo "❌ MISSING: $file"
    ((MISSING_FILES++))
  fi
done

echo ""
if [ $MISSING_FILES -eq 0 ]; then
  echo "✅ All files generated successfully!"
  exit 0
else
  echo "❌ $MISSING_FILES file(s) missing"
  exit 1
fi

