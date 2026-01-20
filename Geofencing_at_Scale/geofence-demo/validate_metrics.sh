#!/bin/bash

echo "Validating Dashboard Metrics..."
echo "================================"

# Wait for services to be ready
sleep 3

# Check API status
echo ""
echo "Checking API Status..."
STATUS=$(curl -s http://localhost:3000/api/status 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ API is not responding"
  exit 1
fi

echo "✅ API is responding"

# Extract metrics using Python
python3 << 'PYTHON_SCRIPT'
import json
import sys
import urllib.request

try:
    with urllib.request.urlopen('http://localhost:3000/api/status') as response:
        data = json.loads(response.read())
        
    metrics = data.get('metrics', {})
    quadtree = metrics.get('quadtree', {})
    geohash = metrics.get('geohash', {})
    
    print("\n📊 Current Metrics:")
    print(f"  Vehicles: {data.get('vehicles', 0)}")
    print(f"  Geofences: {data.get('geofences', 0)}")
    print(f"  Update Count: {metrics.get('updateCount', 0)}")
    print(f"  Boundary Events: {metrics.get('boundaryEvents', 0)}")
    print(f"  QuadTree Queries: {quadtree.get('queriesPerformed', 0)}")
    print(f"  Geohash Queries: {geohash.get('queriesPerformed', 0)}")
    print(f"  QuadTree Query Time: {quadtree.get('queryTime', 0)}ms")
    print(f"  Geohash Query Time: {geohash.get('queryTime', 0)}ms")
    
    # Check if metrics are updating
    issues = []
    if metrics.get('updateCount', 0) == 0:
        issues.append("Update Count is zero")
    if quadtree.get('queriesPerformed', 0) == 0:
        issues.append("QuadTree queries not performed")
    if geohash.get('queriesPerformed', 0) == 0:
        issues.append("Geohash queries not performed")
    
    if issues:
        print("\n⚠️  Issues found:")
        for issue in issues:
            print(f"  - {issue}")
        sys.exit(1)
    else:
        print("\n✅ All metrics are updating!")
        sys.exit(0)
        
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
PYTHON_SCRIPT

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Validation passed - Metrics are updating correctly"
else
    echo ""
    echo "❌ Validation failed - Some metrics are not updating"
fi

exit $EXIT_CODE

