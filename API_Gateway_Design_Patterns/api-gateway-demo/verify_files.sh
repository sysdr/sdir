#!/bin/bash

echo "Verifying all generated files..."
echo "======================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MISSING_FILES=0

check_file() {
    if [ -f "$1" ]; then
        echo "✓ $1"
    else
        echo "✗ MISSING: $1"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
}

echo ""
echo "Checking core files..."
check_file "docker-compose.yml"
check_file "test.sh"

echo ""
echo "Checking Gateway service..."
check_file "gateway/package.json"
check_file "gateway/src/server.js"
check_file "gateway/Dockerfile"

echo ""
echo "Checking User service..."
check_file "user-service/package.json"
check_file "user-service/src/server.js"
check_file "user-service/Dockerfile"

echo ""
echo "Checking Order service..."
check_file "order-service/package.json"
check_file "order-service/src/server.js"
check_file "order-service/Dockerfile"

echo ""
echo "Checking Analytics service..."
check_file "analytics-service/package.json"
check_file "analytics-service/src/server.js"
check_file "analytics-service/Dockerfile"

echo ""
echo "Checking Notification service..."
check_file "notification-service/package.json"
check_file "notification-service/src/server.js"
check_file "notification-service/Dockerfile"

echo ""
echo "Checking Frontend..."
check_file "frontend/src/index.html"
check_file "frontend/Dockerfile"

echo ""
if [ $MISSING_FILES -eq 0 ]; then
    echo "✅ All files are present!"
    exit 0
else
    echo "❌ $MISSING_FILES file(s) missing!"
    exit 1
fi


