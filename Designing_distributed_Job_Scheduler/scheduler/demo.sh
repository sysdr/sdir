#!/bin/bash
# Run from any directory - uses full path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Distributed Job Scheduler Demo ==="
echo ""
echo "The scheduler is running with:"
echo "  • Leader election via Redis"
echo "  • Timing wheel with 60 slots (1 second each)"
echo "  • 3 worker nodes executing tasks"
echo "  • Real-time dashboard at http://localhost:3000"
echo ""
echo "Demo tasks scheduled:"
echo "  1. One-time tasks (emails, payments, reports)"
echo "  2. Recurring tasks (health checks, metrics)"
echo ""
echo "Watch the dashboard to see:"
echo "  ✓ Tasks moving through states: SCHEDULED → PENDING → RUNNING → COMPLETED"
echo "  ✓ Timing wheel advancing every second"
echo "  ✓ Workers claiming and executing tasks"
echo "  ✓ Lease timeouts and retries (5% random failure rate)"
echo "  ✓ Idempotency protection preventing duplicate execution"
echo ""
echo "Open http://localhost:3000 in your browser"
echo ""
echo "Press Ctrl+C to stop the demo"

docker compose logs -f scheduler
