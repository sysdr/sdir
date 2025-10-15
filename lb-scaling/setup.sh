#!/bin/bash
set -e

echo "=================================="
echo "Load Balancer Scaling Demo Setup"
echo "=================================="

# Prerequisite checks
command -v docker >/dev/null 2>&1 || { echo "Docker required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "Docker Compose required but not installed. Aborting." >&2; exit 1; }

# Create project structure
PROJECT_DIR="lb-scaling-demo"
rm -rf $PROJECT_DIR
mkdir -p $PROJECT_DIR/{l4-balancer,l7-balancers,app-servers,monitoring}

echo "✓ Project structure created"

# Generate L4 Load Balancer (HAProxy)
cat > $PROJECT_DIR/l4-balancer/haproxy.cfg <<'EOF'
global
    daemon
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy

defaults
    mode http
    log global
    option httplog
    option dontlognull
    option log-health-checks
    option forwardfor
    option redispatch
    retries 3
    timeout http-request 10s
    timeout queue 20s
    timeout connect 10s
    timeout client 1m
    timeout server 1m
    timeout http-keep-alive 10s
    timeout check 10s
    maxconn 3000

frontend l4_frontend
    bind *:80
    default_backend l7_servers

backend l7_servers
    balance roundrobin
    option httpchk GET /health
    server l7-1 l7-balancer-1:8080 check
    server l7-2 l7-balancer-2:8080 check

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
EOF

cat > $PROJECT_DIR/l4-balancer/Dockerfile <<'EOF'
FROM haproxy:2.8-alpine
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
EOF

echo "✓ L4 Load Balancer configured"

# Generate L7 Load Balancers (Nginx)
for i in 1 2; do
cat > $PROJECT_DIR/l7-balancers/nginx-$i.conf <<EOF
events {
    worker_connections 4096;
}

http {
    upstream app_pool {
        least_conn;
        server app-server-1:3000;
        server app-server-2:3000;
        server app-server-3:3000;
    }

    server {
        listen 8080;
        
        location /health {
            access_log off;
            return 200 "L7-Balancer-$i Healthy\n";
        }

        location / {
            proxy_pass http://app_pool;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_set_header X-Load-Balancer "L7-$i";
        }
    }
}
EOF
done

cat > $PROJECT_DIR/l7-balancers/Dockerfile <<'EOF'
FROM nginx:alpine
COPY nginx-*.conf /etc/nginx/
EOF

echo "✓ L7 Load Balancers configured"

# Generate Application Servers (Node.js)
cat > $PROJECT_DIR/app-servers/server.js <<'EOF'
const http = require('http');
const os = require('os');

const hostname = os.hostname();
let requestCount = 0;

const server = http.createServer((req, res) => {
  requestCount++;
  
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('OK');
    return;
  }

  // Simulate some processing
  const start = Date.now();
  while (Date.now() - start < 10) {} // 10ms busy work
  
  const response = {
    server: hostname,
    requestNumber: requestCount,
    loadBalancer: req.headers['x-load-balancer'] || 'unknown',
    timestamp: new Date().toISOString()
  };
  
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(response, null, 2));
});

server.listen(3000, () => {
  console.log(`Server ${hostname} running on port 3000`);
});
EOF

cat > $PROJECT_DIR/app-servers/Dockerfile <<'EOF'
FROM node:18-alpine
WORKDIR /app
COPY server.js .
CMD ["node", "server.js"]
EOF

echo "✓ Application servers configured"

# Generate Docker Compose
cat > $PROJECT_DIR/docker-compose.yml <<'EOF'
services:
  l4-balancer:
    build: ./l4-balancer
    ports:
      - "8000:80"
      - "8404:8404"
    depends_on:
      - l7-balancer-1
      - l7-balancer-2
    networks:
      - lb-network

  l7-balancer-1:
    build:
      context: ./l7-balancers
    command: nginx -c /etc/nginx/nginx-1.conf -g "daemon off;"
    depends_on:
      - app-server-1
      - app-server-2
      - app-server-3
    networks:
      - lb-network

  l7-balancer-2:
    build:
      context: ./l7-balancers
    command: nginx -c /etc/nginx/nginx-2.conf -g "daemon off;"
    depends_on:
      - app-server-1
      - app-server-2
      - app-server-3
    networks:
      - lb-network

  app-server-1:
    build: ./app-servers
    networks:
      - lb-network

  app-server-2:
    build: ./app-servers
    networks:
      - lb-network

  app-server-3:
    build: ./app-servers
    networks:
      - lb-network

networks:
  lb-network:
    driver: bridge
EOF

echo "✓ Docker Compose orchestration configured"

# Generate test script
cat > $PROJECT_DIR/test-load-distribution.sh <<'EOF'
#!/bin/bash
echo "Testing load distribution across the hierarchy..."
echo "=================================================="

for i in {1..12}; do
  echo "Request $i:"
  curl -s http://localhost:8000/ | jq -r '"\(.loadBalancer) -> \(.server)"'
  sleep 0.5
done

echo ""
echo "Testing L7 health endpoints directly:"
docker exec lb-scaling-demo-l7-balancer-1-1 curl -s http://localhost:8080/health
docker exec lb-scaling-demo-l7-balancer-2-1 curl -s http://localhost:8080/health
EOF

chmod +x $PROJECT_DIR/test-load-distribution.sh

echo "✓ Test scripts generated"

# Build and start
cd $PROJECT_DIR
echo ""
echo "Building containers..."
docker-compose build --quiet

echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 5

# Run tests
echo ""
./test-load-distribution.sh

echo ""
echo "=================================="
echo "✓ Setup Complete!"
echo "=================================="
echo ""
echo "Access your load-balanced service at: http://localhost:8000"
echo ""
echo "Architecture deployed:"
echo "  1 L4 Load Balancer (HAProxy) - Port 8000"
echo "  2 L7 Load Balancers (Nginx) - Internal routing"
echo "  3 Application Servers (Node.js) - Processing requests"
echo ""
echo "To test manually: curl http://localhost:8000"
echo "To view logs: cd $PROJECT_DIR && docker-compose logs -f"
echo "To stop: cd $PROJECT_DIR && docker-compose down"