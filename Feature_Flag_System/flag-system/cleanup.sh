#!/bin/bash
echo "Cleaning up Feature Flag System..."
docker-compose down -v
echo "✓ Cleanup complete"
