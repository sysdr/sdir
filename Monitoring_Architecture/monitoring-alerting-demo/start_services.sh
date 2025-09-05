#!/bin/bash

echo "🚀 Starting all services with proper networking..."

# Start monitoring infrastructure
docker run -d --name prometheus --network monitoring-network -p 9090:9090 -v $(pwd)/monitoring/prometheus:/etc/prometheus prom/prometheus:v2.48.0 --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --web.console.libraries=/etc/prometheus/console_libraries --web.console.templates=/etc/prometheus/consoles --storage.tsdb.retention.time=200h --web.enable-lifecycle --web.enable-admin-api

docker run -d --name alertmanager --network monitoring-network -p 9093:9093 -v $(pwd)/monitoring/alertmanager:/etc/alertmanager prom/alertmanager:v0.26.0

docker run -d --name grafana --network monitoring-network -p 3000:3000 -e GF_SECURITY_ADMIN_PASSWORD=admin -e GF_USERS_ALLOW_SIGN_UP=false -v $(pwd)/monitoring/grafana:/etc/grafana/provisioning grafana/grafana:10.2.2

# Start microservices
docker run -d --name user-service --network monitoring-network -p 8001:8000 -e SERVICE_NAME=user-service -e FAILURE_RATE=0.02 user-service

docker run -d --name payment-service --network monitoring-network -p 8002:8000 -e SERVICE_NAME=payment-service -e FAILURE_RATE=0.05 payment-service

docker run -d --name order-service --network monitoring-network -p 8003:8000 -e SERVICE_NAME=order-service -e FAILURE_RATE=0.01 order-service

# Start web dashboard
docker run -d --name web-dashboard --network monitoring-network -p 8080:8080 web-dashboard

# Start load generator
docker run -d --name load-generator --network monitoring-network load-generator

echo "✅ All services started!"
echo "📱 Access Points:"
echo "   Dashboard:    http://localhost:8080"
echo "   Grafana:      http://localhost:3000 (admin/admin)"
echo "   Prometheus:   http://localhost:9090"
echo "   AlertManager: http://localhost:9093"
