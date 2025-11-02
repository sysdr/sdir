#!/bin/bash

echo "🧪 Running Geospatial System Tests..."

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Test Location Service
echo "📍 Testing Location Service..."
curl -X POST http://localhost:8000/api/location/update \
  -H "Content-Type: application/json" \
  -d '{"driverId":"test_driver","lat":40.7128,"lon":-74.0060,"status":"available"}'

echo ""
echo "🔍 Testing Proximity Search..."
curl "http://localhost:8000/api/location/nearby?lat=40.7128&lon=-74.0060&radius=5000"

echo ""
echo "🚧 Testing Geofence Service..."
curl "http://localhost:8001/api/geofence/check?lat=40.7128&lon=-74.0060"

echo ""
echo "📊 Testing Proximity Service..."
curl -X POST http://localhost:8002/api/proximity/knn \
  -H "Content-Type: application/json" \
  -d '{"lat":40.7128,"lon":-74.0060,"k":5}'

echo ""
echo "✅ All tests completed!"
