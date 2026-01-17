#!/bin/bash

echo "🎬 Starting CRDT vs OT Demo..."
echo ""
echo "The demo is running at:"
echo "  🌐 http://localhost:3000"
echo ""
echo "Features:"
echo "  • Side-by-side comparison of OT and CRDT"
echo "  • Real-time collaborative editing"
echo "  • Conflict simulation with 3 virtual users"
echo "  • Live metrics and operation logs"
echo ""
echo "Try this:"
echo "  1. Type in either editor to see synchronization"
echo "  2. Click simulator buttons to create conflicts"
echo "  3. Watch how OT transforms via server vs CRDT peer sync"
echo "  4. Check metrics for version numbers and state size"
echo ""
echo "Press Ctrl+C to stop the demo"
echo ""

# Keep script running
tail -f /dev/null
