#!/bin/bash
DEMO_URL="http://localhost:4210"
echo "Demo URL: $DEMO_URL"
if command -v xdg-open &>/dev/null; then xdg-open "$DEMO_URL" 2>/dev/null || echo "Visit: $DEMO_URL"
elif command -v open &>/dev/null; then open "$DEMO_URL" 2>/dev/null || echo "Visit: $DEMO_URL"
else echo "Visit: $DEMO_URL"; fi
exit 0
