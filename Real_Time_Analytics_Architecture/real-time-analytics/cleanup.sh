#!/bin/bash

echo "Cleaning up Real-Time Analytics demo..."
docker-compose down -v
echo "✓ Containers stopped and volumes removed"
