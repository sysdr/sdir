#!/bin/bash

echo "🧹 Cleaning up K8s-Native Application Demo..."

kind delete cluster --name k8s-native
docker rmi k8s-native-app:latest k8s-dashboard:latest 2>/dev/null

echo "✅ Cleanup complete!"

