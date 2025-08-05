#!/bin/bash

echo "🔍 Verifying demo setup..."

# Check all required files exist
files=(
    "package.json"
    "src/app.js"
    "dashboard/index.html"
    "docker-compose.yml"
    "Dockerfile"
    "demo.sh"
    "cleanup.sh"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ $file is missing"
        exit 1
    fi
done

# Test Docker Compose configuration
echo "🐳 Validating Docker Compose..."
docker-compose config >/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Docker Compose configuration is valid"
else
    echo "❌ Docker Compose configuration has errors"
    exit 1
fi

echo "🎉 Demo setup verified successfully!"
echo ""
echo "Next steps:"
echo "1. Run: ./demo.sh"
echo "2. Open: http://localhost:8000"
echo "3. Experiment with failure scenarios"
echo "4. Run: ./cleanup.sh (when done)"
