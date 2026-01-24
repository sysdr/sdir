#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "Building Developer Platform"
echo "======================================"

# Step 1: Run setup script to generate all files
echo ""
echo "Step 1: Generating project files..."
if [ ! -f "setup.sh" ]; then
    echo "❌ Error: setup.sh not found!"
    exit 1
fi

bash setup.sh

# Step 2: Verify files were generated
echo ""
echo "Step 2: Verifying generated files..."
DEV_PLATFORM_DIR="${SCRIPT_DIR}/dev-platform"

REQUIRED_FILES=(
    "dev-platform/catalog/server.js"
    "dev-platform/catalog/package.json"
    "dev-platform/catalog/Dockerfile"
    "dev-platform/deployer/server.js"
    "dev-platform/deployer/package.json"
    "dev-platform/deployer/Dockerfile"
    "dev-platform/metrics/server.js"
    "dev-platform/metrics/package.json"
    "dev-platform/metrics/Dockerfile"
    "dev-platform/portal/package.json"
    "dev-platform/portal/Dockerfile"
    "dev-platform/portal/public/index.html"
    "dev-platform/portal/src/index.js"
    "dev-platform/portal/src/App.js"
    "dev-platform/portal/src/App.css"
    "dev-platform/docker-compose.yml"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "❌ Error: Missing required files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "   - $file"
    done
    exit 1
fi

echo "✅ All required files generated"

# Step 3: Build Docker containers
echo ""
echo "Step 3: Building Docker containers..."
cd "$DEV_PLATFORM_DIR"

if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

# Use docker compose (newer) or docker-compose (older)
if command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ Error: docker-compose not found"
    exit 1
fi

echo "Building containers (this may take a few minutes)..."
$DOCKER_COMPOSE build

if [ $? -ne 0 ]; then
    echo "❌ Error: Docker build failed"
    exit 1
fi

echo "✅ Docker containers built successfully"

# Step 4: Summary
echo ""
echo "======================================"
echo "✅ Build completed successfully!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  To start services: ./start-services.sh"
echo "  To run tests:      ./test-services.sh"
echo "  To clean up:       ./cleanup.sh"
echo ""

