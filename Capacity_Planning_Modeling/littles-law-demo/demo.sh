#!/bin/bash
echo "🚀 Starting Little's Law Load Generator (10 RPS for 120s)..."
cd "$(dirname "$0")"
docker compose --profile load up load-generator --no-deps
