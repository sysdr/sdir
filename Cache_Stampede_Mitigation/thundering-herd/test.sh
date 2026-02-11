#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "tests/test-stampede.sh" ]; then
    echo "⚠️  tests/test-stampede.sh not found."
    exit 1
fi

exec bash "$SCRIPT_DIR/tests/test-stampede.sh"
