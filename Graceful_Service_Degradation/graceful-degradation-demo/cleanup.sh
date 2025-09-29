#!/bin/bash

echo "🧹 Cleaning up Graceful Degradation Demo..."

# Check if Docker was used
if docker-compose ps >/dev/null 2>&1; then
    echo "🐳 Stopping Docker services..."
    docker-compose down
    docker-compose rm -f
else
    # Kill local processes
    if [[ -f .demo_pids ]]; then
        echo "🔪 Stopping local services..."
        PIDS=$(cat .demo_pids)
        for pid in $PIDS; do
            kill $pid 2>/dev/null || true
        done
        rm .demo_pids
    fi
fi

echo "✅ Cleanup complete!"
