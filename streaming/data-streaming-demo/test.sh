#!/bin/bash
set -e

echo "Running tests..."

# Run unit tests
python -m pytest tests/ -v --tb=short

# Run integration tests
echo "Running integration tests..."
python -m unittest tests.test_streaming -v

echo "All tests passed!"
