#!/bin/bash
echo "Cleaning up IAM demo..."
docker-compose down -v
echo "✓ All containers and volumes removed"
