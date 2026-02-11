#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d "thundering-herd" ]; then
    echo "⚠️  thundering-herd not found. Run ./setup.sh or ./build.sh first."
    exit 1
fi

if [ ! -f "thundering-herd/tests/test-stampede.sh" ]; then
    echo "⚠️  thundering-herd/tests/test-stampede.sh not found."
    exit 1
fi
exec bash "$SCRIPT_DIR/thundering-herd/tests/test-stampede.sh"
