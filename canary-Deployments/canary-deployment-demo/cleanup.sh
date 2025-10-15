#!/bin/bash

echo "🧹 Starting cleanup for checkin..."

# Remove any temporary files that might have been created during testing
echo "📁 Cleaning temporary files..."
find . -name "*.log" -delete 2>/dev/null || true
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "*.cache" -delete 2>/dev/null || true
find . -name "*.pid" -delete 2>/dev/null || true
find . -name "*.lock" -delete 2>/dev/null || true
find . -name ".DS_Store" -delete 2>/dev/null || true
find . -name "*.swp" -delete 2>/dev/null || true
find . -name "*.swo" -delete 2>/dev/null || true
find . -name "*~" -delete 2>/dev/null || true

# Remove any build artifacts (but preserve source code)
echo "🔨 Cleaning build artifacts..."
find . -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "build" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name ".next" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "coverage" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name ".nyc_output" -exec rm -rf {} + 2>/dev/null || true

# Remove any environment files that might contain secrets
echo "🔒 Cleaning sensitive files..."
find . -name ".env*" -delete 2>/dev/null || true
find . -name "config.local*" -delete 2>/dev/null || true
find . -name "secrets*" -delete 2>/dev/null || true
find . -name "*.key" -delete 2>/dev/null || true
find . -name "*.pem" -delete 2>/dev/null || true
find . -name "*.crt" -delete 2>/dev/null || true

# Clean up any Docker artifacts (but preserve docker-compose.yml and Dockerfiles)
echo "🐳 Cleaning Docker artifacts..."
docker system prune -f 2>/dev/null || true

# Remove any empty directories
echo "📂 Cleaning empty directories..."
find . -type d -empty -delete 2>/dev/null || true

echo "✅ Cleanup completed successfully!"
echo "📋 Important files preserved:"
echo "   - All source code files (.js, .py, .sh, etc.)"
echo "   - Configuration files (docker-compose.yml, nginx.conf, etc.)"
echo "   - Documentation and README files"
echo "   - Dockerfiles and deployment scripts"
echo ""
echo "🚀 Repository is ready for checkin!"
