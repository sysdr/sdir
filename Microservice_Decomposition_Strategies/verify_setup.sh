#!/bin/bash
# Verification script to check if setup.sh generated all required files

echo "=== Verifying Setup Script Output ==="
echo ""

ERRORS=0

# Check directory structure
echo "Checking directory structure..."
DIRS=("monolith" "services/order" "services/payment" "services/inventory" "strangler/gateway" "strangler/legacy" "strangler/new-services" "shared")
for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "  ❌ Missing directory: $dir"
        ((ERRORS++))
    else
        echo "  ✅ Directory exists: $dir"
    fi
done

echo ""
echo "Checking package.json files..."
PKG_FILES=("monolith/package.json" "services/order/package.json" "services/payment/package.json" "services/inventory/package.json" "strangler/gateway/package.json" "strangler/legacy/package.json" "strangler/new-services/package.json")
for file in "${PKG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ❌ Missing: $file"
        ((ERRORS++))
    else
        echo "  ✅ Exists: $file"
    fi
done

echo ""
echo "Checking server.js files..."
SERVER_FILES=("monolith/server.js" "services/order/server.js" "services/payment/server.js" "services/inventory/server.js" "strangler/gateway/server.js" "strangler/legacy/server.js" "strangler/new-services/server.js")
for file in "${SERVER_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ❌ Missing: $file"
        ((ERRORS++))
    else
        echo "  ✅ Exists: $file"
    fi
done

echo ""
echo "Checking Dockerfiles..."
DOCKERFILES=("monolith/Dockerfile" "services/order/Dockerfile" "services/payment/Dockerfile" "services/inventory/Dockerfile" "strangler/gateway/Dockerfile" "strangler/legacy/Dockerfile" "strangler/new-services/Dockerfile")
for file in "${DOCKERFILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ❌ Missing: $file"
        ((ERRORS++))
    else
        echo "  ✅ Exists: $file"
    fi
done

echo ""
echo "Checking other files..."
OTHER_FILES=("docker-compose.yml" "shared/index.html")
for file in "${OTHER_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ❌ Missing: $file"
        ((ERRORS++))
    else
        echo "  ✅ Exists: $file"
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All required files are present!"
    exit 0
else
    echo "❌ Found $ERRORS missing files!"
    exit 1
fi

