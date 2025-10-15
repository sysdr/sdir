#!/bin/bash

echo "🚀 Building and starting Monitoring & Alerting Demo..."

# Build and start services
echo "📦 Building Docker images..."
docker compose build

echo "🔄 Starting services..."
docker compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

echo "🧪 Running tests..."
python3 test_demo.py

echo "
✅ Demo is ready!

📱 Access Points:
   🎛️  Dashboard:    http://localhost:8080
   📊 Grafana:      http://localhost:3000 (admin/admin)  
   📈 Prometheus:   http://localhost:9090
   🚨 AlertManager: http://localhost:9093

🔍 What to explore:
   1. Visit the dashboard to see real-time metrics
   2. Check Grafana for detailed monitoring charts
   3. Watch alerts in the dashboard as load generates
   4. Explore SLO burn rate monitoring
   5. Test alert correlation and escalation

📖 Key Learning Points:
   ✓ Multi-tier alerting (Tier 1: Critical, Tier 2: Warning, Tier 3: Info)
   ✓ SLO-based monitoring with error budget tracking
   ✓ Alert correlation and grouping
   ✓ Escalation policies based on severity
   ✓ Context-rich alerting with runbook integration

🔥 To simulate failures:
   docker-compose stop payment-service
   docker-compose start payment-service
"
