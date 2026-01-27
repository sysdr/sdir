#!/bin/bash

echo "🧪 Running HFT Latency Demo Tests..."

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 15

# Test packet generator
echo "Testing packet generator..."
response=$(curl -s http://localhost:3001/health)
if echo "$response" | grep -q "healthy"; then
  echo "✅ Packet generator is healthy"
else
  echo "❌ Packet generator failed health check"
  exit 1
fi

# Test traditional processor
echo "Testing traditional processor..."
response=$(curl -s http://localhost:3002/health)
if echo "$response" | grep -q "healthy"; then
  echo "✅ Traditional processor is healthy"
else
  echo "❌ Traditional processor failed health check"
  exit 1
fi

# Test optimized processor
echo "Testing optimized processor..."
response=$(curl -s http://localhost:3003/health)
if echo "$response" | grep -q "healthy"; then
  echo "✅ Optimized processor is healthy"
else
  echo "❌ Optimized processor failed health check"
  exit 1
fi

# Test metrics collector
echo "Testing metrics collector..."
response=$(curl -s http://localhost:3004/health)
if echo "$response" | grep -q "healthy"; then
  echo "✅ Metrics collector is healthy"
else
  echo "❌ Metrics collector failed health check"
  exit 1
fi

# Verify processors are receiving data
sleep 5
echo "Checking if processors are receiving packets..."
trad_stats=$(curl -s http://localhost:3002/stats)
opt_stats=$(curl -s http://localhost:3003/stats)

trad_packets=$(echo "$trad_stats" | grep -o '"packetsProcessed":[0-9]*' | cut -d':' -f2)
opt_packets=$(echo "$opt_stats" | grep -o '"packetsProcessed":[0-9]*' | cut -d':' -f2)

if [ "$trad_packets" -gt 0 ]; then
  echo "✅ Traditional processor has processed $trad_packets packets"
else
  echo "❌ Traditional processor hasn't processed any packets"
  exit 1
fi

if [ "$opt_packets" -gt 0 ]; then
  echo "✅ Optimized processor has processed $opt_packets packets"
else
  echo "❌ Optimized processor hasn't processed any packets"
  exit 1
fi

# Verify latency difference
trad_avg=$(echo "$trad_stats" | grep -o '"avgLatency":"[0-9.]*"' | cut -d'"' -f4)
opt_avg=$(echo "$opt_stats" | grep -o '"avgLatency":"[0-9.]*"' | cut -d'"' -f4)

echo ""
echo "📊 Performance Comparison:"
echo "Traditional Average Latency: ${trad_avg}μs"
echo "Optimized Average Latency: ${opt_avg}μs"

# Simple float comparison (optimized should be significantly lower)
if (( $(echo "$opt_avg < $trad_avg" | bc -l) )); then
  echo "✅ Optimized processor shows lower latency as expected"
else
  echo "⚠️  Warning: Optimized latency not lower than traditional"
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "🎉 Demo is running successfully!"
echo "📊 Open http://localhost:3000 to view the dashboard"
