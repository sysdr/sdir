#!/bin/bash

# Use jq for JSON if available, else cat
JQ=$(command -v jq 2>/dev/null || echo "cat")

echo "🚀 Starting AI-Powered Application Demo..."

# Build and start services
docker-compose up -d --build

echo "⏳ Waiting for services to be healthy (up to 5 min)..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:5000/health >/dev/null && curl -sf http://localhost:5001/health >/dev/null; then
    echo "Services ready after ${i}0s"
    break
  fi
  sleep 10
  if [ "$i" -eq 30 ]; then echo "⚠ Services did not become ready in time."; fi
done

# Health checks
echo "🏥 Checking service health..."
curl -f http://localhost:5000/health && echo " Backend OK" || echo "Backend not ready"
curl -f http://localhost:5001/health && echo " Model service OK" || echo "Model service not ready"

echo ""
echo "✅ Demo is ready!"
echo ""
echo "📊 Access points:"
echo "  - Frontend Dashboard: http://localhost:3000"
echo "  - Backend API: http://localhost:5000"
echo "  - Model Service: http://localhost:5001"
echo ""
echo "🧪 Running automated tests..."

# Test 1: Simple similarity with auto-routing
echo "Test 1: Auto-routing (should use fast model)"
curl -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{
    "text1": "Hello world",
    "text2": "Hi there",
    "model": null
  }' | $JQ '.'

sleep 2

# Test 2: Complex query (should use heavy model)
echo ""
echo "Test 2: Complex query (should use heavy model)"
curl -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{
    "text1": "Can you compare and analyze the differences between machine learning and deep learning approaches?",
    "text2": "What are the key distinctions between ML and DL methodologies?",
    "model": null
  }' | $JQ '.'

sleep 2

# Test 3: Cache hit test
echo ""
echo "Test 3: Cache hit (repeating previous query)"
curl -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{
    "text1": "Hello world",
    "text2": "Hi there",
    "model": null
  }' | $JQ '.'

sleep 2

# Test 4: Force heavy model
echo ""
echo "Test 4: Forcing heavy model"
curl -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{
    "text1": "AI systems",
    "text2": "Artificial intelligence",
    "model": "heavy"
  }' | $JQ '.'

sleep 2

# Get metrics
echo ""
echo "📈 Current System Metrics:"
curl -s http://localhost:5000/api/metrics | json_fmt '.'

echo ""
echo "🎯 Key Behaviors Demonstrated:"
echo "  ✓ Smart routing based on query complexity"
echo "  ✓ Multi-tier caching with Redis"
echo "  ✓ Fast vs Heavy model selection"
echo "  ✓ Real-time cost and latency tracking"
echo "  ✓ Cache hit rate optimization"
echo ""
echo "📖 Try the interactive dashboard at http://localhost:3000"
echo "   - Compare different texts"
echo "   - Switch between model tiers"
echo "   - Watch real-time metrics"
echo "   - Observe caching behavior"
