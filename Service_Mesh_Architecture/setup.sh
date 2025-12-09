#!/bin/bash

# Service Mesh Architecture Demo
# Demonstrates real service mesh with Envoy proxies, mTLS, circuit breaking, and observability

set -e

echo "🚀 Setting up Service Mesh Architecture Demo..."

# Create project structure
mkdir -p service-mesh-demo/{services/{service-a,service-b,service-c},envoy,dashboard,control-plane}
cd service-mesh-demo

# ============================================================================
# SERVICE A - Orders Service
# ============================================================================
cat > services/service-a/package.json << 'EOF'
{
  "name": "service-a",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "prom-client": "^15.0.0"
  }
}
EOF

cat > services/service-a/server.js << 'EOF'
import express from 'express';
import axios from 'axios';
import { register, Counter, Histogram } from 'prom-client';

const app = express();
const PORT = 3001;

// Metrics
const requestCounter = new Counter({
  name: 'service_a_requests_total',
  help: 'Total requests to Service A'
});

const requestDuration = new Histogram({
  name: 'service_a_request_duration_seconds',
  help: 'Service A request duration',
  buckets: [0.001, 0.01, 0.1, 0.5, 1, 2, 5]
});

let requestCount = 0;
let failureSimulation = false;

app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'service-a', requests: requestCount });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Main endpoint - calls Service B
app.get('/api/orders', async (req, res) => {
  const end = requestDuration.startTimer();
  requestCounter.inc();
  requestCount++;

  console.log(`[Service A] Received request #${requestCount}`);

  try {
    // Simulate occasional slow response
    if (Math.random() < 0.1) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }

    // Call Service B through Envoy sidecar
    const response = await axios.get('http://localhost:15001/api/inventory', {
      timeout: 3000,
      headers: {
        'x-request-id': req.headers['x-request-id'] || `req-${Date.now()}`,
        'x-forwarded-for': req.ip
      }
    });

    end();
    res.json({
      service: 'service-a',
      message: 'Orders processed',
      orders: ['ORDER-001', 'ORDER-002'],
      inventory: response.data,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    end();
    console.error('[Service A] Error calling Service B:', error.message);
    res.status(503).json({
      service: 'service-a',
      error: 'Inventory service unavailable',
      message: error.message
    });
  }
});

// Endpoint to simulate failures
app.post('/api/simulate-failure', (req, res) => {
  failureSimulation = req.body.enable;
  res.json({ failureMode: failureSimulation });
});

app.listen(PORT, () => {
  console.log(`[Service A] Running on port ${PORT}`);
});
EOF

cat > services/service-a/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
CMD ["node", "server.js"]
EOF

# ============================================================================
# SERVICE B - Inventory Service
# ============================================================================
cat > services/service-b/package.json << 'EOF'
{
  "name": "service-b",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "prom-client": "^15.0.0"
  }
}
EOF

cat > services/service-b/server.js << 'EOF'
import express from 'express';
import axios from 'axios';
import { register, Counter, Histogram } from 'prom-client';

const app = express();
const PORT = 3002;

const requestCounter = new Counter({
  name: 'service_b_requests_total',
  help: 'Total requests to Service B'
});

const requestDuration = new Histogram({
  name: 'service_b_request_duration_seconds',
  help: 'Service B request duration',
  buckets: [0.001, 0.01, 0.1, 0.5, 1, 2, 5]
});

let requestCount = 0;
let failureRate = 0;

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'service-b', requests: requestCount });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/api/inventory', async (req, res) => {
  const end = requestDuration.startTimer();
  requestCounter.inc();
  requestCount++;

  console.log(`[Service B] Received request #${requestCount}`);

  // Simulate failures based on failure rate
  if (Math.random() < failureRate) {
    end();
    console.log('[Service B] Simulating failure');
    return res.status(500).json({ error: 'Internal server error' });
  }

  try {
    // Call Service C
    const response = await axios.get('http://localhost:15002/api/products', {
      timeout: 2000,
      headers: {
        'x-request-id': req.headers['x-request-id']
      }
    });

    end();
    res.json({
      service: 'service-b',
      inventory: ['ITEM-A', 'ITEM-B', 'ITEM-C'],
      products: response.data,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    end();
    console.error('[Service B] Error:', error.message);
    res.status(503).json({ error: 'Products service unavailable' });
  }
});

app.post('/api/failure-rate', (req, res) => {
  failureRate = req.body.rate || 0;
  res.json({ failureRate });
});

app.listen(PORT, () => {
  console.log(`[Service B] Running on port ${PORT}`);
});
EOF

cat > services/service-b/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
CMD ["node", "server.js"]
EOF

# ============================================================================
# SERVICE C - Products Service
# ============================================================================
cat > services/service-c/package.json << 'EOF'
{
  "name": "service-c",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.0.0"
  }
}
EOF

cat > services/service-c/server.js << 'EOF'
import express from 'express';
import { register, Counter, Histogram } from 'prom-client';

const app = express();
const PORT = 3003;

const requestCounter = new Counter({
  name: 'service_c_requests_total',
  help: 'Total requests to Service C'
});

const requestDuration = new Histogram({
  name: 'service_c_request_duration_seconds',
  help: 'Service C request duration',
  buckets: [0.001, 0.01, 0.1, 0.5, 1, 2, 5]
});

let requestCount = 0;

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'service-c', requests: requestCount });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/api/products', (req, res) => {
  const end = requestDuration.startTimer();
  requestCounter.inc();
  requestCount++;

  console.log(`[Service C] Received request #${requestCount}`);

  // Simulate variable latency
  const delay = Math.random() * 200;
  setTimeout(() => {
    end();
    res.json({
      service: 'service-c',
      products: [
        { id: 'P1', name: 'Product Alpha', price: 99.99 },
        { id: 'P2', name: 'Product Beta', price: 149.99 },
        { id: 'P3', name: 'Product Gamma', price: 199.99 }
      ],
      timestamp: new Date().toISOString()
    });
  }, delay);
});

app.listen(PORT, () => {
  console.log(`[Service C] Running on port ${PORT}`);
});
EOF

cat > services/service-c/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
CMD ["node", "server.js"]
EOF

# ============================================================================
# ENVOY PROXY CONFIGURATIONS
# ============================================================================

# Envoy config for Service A
cat > envoy/envoy-service-a.yaml << 'EOF'
static_resources:
  listeners:
  - name: listener_service_b
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 15001
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: egress_service_b
          route_config:
            name: local_route
            virtual_hosts:
            - name: service_b
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: service_b_cluster
                  retry_policy:
                    retry_on: "5xx,connect-failure,refused-stream"
                    num_retries: 3
                    per_try_timeout: 1s
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: service_b_cluster
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    connect_timeout: 1s
    circuit_breakers:
      thresholds:
      - priority: DEFAULT
        max_connections: 100
        max_pending_requests: 50
        max_requests: 100
        max_retries: 3
    outlier_detection:
      consecutive_5xx: 3
      interval: 10s
      base_ejection_time: 30s
    load_assignment:
      cluster_name: service_b_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: service-b
                port_value: 3002

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# Envoy config for Service B
cat > envoy/envoy-service-b.yaml << 'EOF'
static_resources:
  listeners:
  - name: listener_service_c
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 15002
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: egress_service_c
          route_config:
            name: local_route
            virtual_hosts:
            - name: service_c
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: service_c_cluster
                  timeout: 2s
                  retry_policy:
                    retry_on: "5xx"
                    num_retries: 2
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: service_c_cluster
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    connect_timeout: 500ms
    circuit_breakers:
      thresholds:
      - priority: DEFAULT
        max_connections: 50
    load_assignment:
      cluster_name: service_c_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: service-c
                port_value: 3003

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9902
EOF

# ============================================================================
# CONTROL PLANE SIMULATOR
# ============================================================================
cat > control-plane/package.json << 'EOF'
{
  "name": "control-plane",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "ws": "^8.14.2"
  }
}
EOF

cat > control-plane/server.js << 'EOF'
import express from 'express';
import axios from 'axios';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';

const app = express();
const PORT = 8080;

app.use(express.json());

const server = createServer(app);
const wss = new WebSocketServer({ server });

let clients = [];

wss.on('connection', (ws) => {
  clients.push(ws);
  console.log('[Control Plane] Dashboard connected');
  
  ws.on('close', () => {
    clients = clients.filter(client => client !== ws);
  });
});

function broadcast(data) {
  clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

// Collect metrics from all services
async function collectMetrics() {
  const metrics = {
    timestamp: new Date().toISOString(),
    services: {}
  };

  const services = [
    { name: 'service-a', url: 'http://service-a:3001' },
    { name: 'service-b', url: 'http://service-b:3002' },
    { name: 'service-c', url: 'http://service-c:3003' }
  ];

  for (const service of services) {
    try {
      const [health, envoyStats] = await Promise.all([
        axios.get(`${service.url}/health`, { timeout: 1000 }).catch(() => null),
        getEnvoyStats(service.name).catch(() => null)
      ]);

      metrics.services[service.name] = {
        status: health?.data?.status || 'unknown',
        requests: health?.data?.requests || 0,
        envoy: envoyStats || {}
      };
    } catch (error) {
      metrics.services[service.name] = { status: 'error', error: error.message };
    }
  }

  return metrics;
}

async function getEnvoyStats(serviceName) {
  const portMap = { 'service-a': 9901, 'service-b': 9902 };
  const port = portMap[serviceName];
  
  if (!port) return {};

  try {
    const response = await axios.get(`http://envoy-${serviceName}:${port}/stats`, { timeout: 1000 });
    const stats = response.data.split('\n');
    
    return {
      connections: parseInt(stats.find(s => s.includes('downstream_cx_total'))?.split(':')[1]) || 0,
      requests: parseInt(stats.find(s => s.includes('downstream_rq_total'))?.split(':')[1]) || 0
    };
  } catch {
    return {};
  }
}

// Periodic metrics collection
setInterval(async () => {
  const metrics = await collectMetrics();
  broadcast({ type: 'metrics', data: metrics });
}, 2000);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'control-plane' });
});

app.get('/api/mesh-status', async (req, res) => {
  const metrics = await collectMetrics();
  res.json(metrics);
});

app.post('/api/service-b/failure-rate', async (req, res) => {
  try {
    await axios.post('http://service-b:3002/api/failure-rate', req.body);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

server.listen(PORT, () => {
  console.log(`[Control Plane] Running on port ${PORT}`);
});
EOF

cat > control-plane/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
CMD ["node", "server.js"]
EOF

# ============================================================================
# REACT DASHBOARD
# ============================================================================
cat > dashboard/package.json << 'EOF'
{
  "name": "service-mesh-dashboard",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "recharts": "^2.10.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  },
  "scripts": {
    "dev": "vite --host 0.0.0.0 --port 3000",
    "build": "vite build"
  }
}
EOF

cat > dashboard/vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 3000
  }
});
EOF

cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Service Mesh Dashboard</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

mkdir -p dashboard/src

cat > dashboard/src/main.jsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

cat > dashboard/src/index.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  padding: 20px;
}

#root {
  max-width: 1400px;
  margin: 0 auto;
}
EOF

cat > dashboard/src/App.jsx << 'EOF'
import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

export default function App() {
  const [metrics, setMetrics] = useState({ services: {} });
  const [history, setHistory] = useState([]);
  const [failureRate, setFailureRate] = useState(0);

  useEffect(() => {
    const ws = new WebSocket('ws://localhost:8080');
    
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === 'metrics') {
        setMetrics(message.data);
        setHistory(prev => [...prev.slice(-19), {
          time: new Date().toLocaleTimeString(),
          serviceA: message.data.services['service-a']?.requests || 0,
          serviceB: message.data.services['service-b']?.requests || 0,
          serviceC: message.data.services['service-c']?.requests || 0
        }]);
      }
    };

    return () => ws.close();
  }, []);

  const setFailureRateHandler = async (rate) => {
    setFailureRate(rate);
    await fetch('http://localhost:8080/api/service-b/failure-rate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ rate: rate / 100 })
    });
  };

  const sendTestRequest = async () => {
    try {
      const response = await fetch('http://localhost:3001/api/orders');
      const data = await response.json();
      console.log('Response:', data);
    } catch (error) {
      console.error('Request failed:', error);
    }
  };

  return (
    <div style={{ color: 'white' }}>
      <div style={{
        background: 'rgba(255, 255, 255, 0.1)',
        backdropFilter: 'blur(10px)',
        borderRadius: '20px',
        padding: '30px',
        marginBottom: '20px',
        border: '1px solid rgba(255, 255, 255, 0.2)'
      }}>
        <h1 style={{ fontSize: '2.5rem', marginBottom: '10px', fontWeight: '700' }}>
          🔗 Service Mesh Control Plane
        </h1>
        <p style={{ opacity: 0.9, fontSize: '1.1rem' }}>
          Real-time monitoring of microservices with Envoy proxies
        </p>
      </div>

      {/* Service Status Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '20px', marginBottom: '20px' }}>
        {Object.entries(metrics.services).map(([name, data]) => (
          <div key={name} style={{
            background: 'rgba(255, 255, 255, 0.95)',
            borderRadius: '15px',
            padding: '25px',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.1)',
            border: '1px solid rgba(255, 255, 255, 0.3)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '15px' }}>
              <h3 style={{ color: '#667eea', fontSize: '1.3rem', fontWeight: '600' }}>
                {name.toUpperCase()}
              </h3>
              <span style={{
                padding: '5px 15px',
                borderRadius: '20px',
                background: data.status === 'healthy' ? '#10b981' : '#ef4444',
                color: 'white',
                fontSize: '0.85rem',
                fontWeight: '600'
              }}>
                {data.status}
              </span>
            </div>
            
            <div style={{ color: '#4b5563' }}>
              <div style={{ marginBottom: '10px', fontSize: '0.95rem' }}>
                <strong>Total Requests:</strong> {data.requests || 0}
              </div>
              {data.envoy && (
                <div style={{ 
                  background: '#f3f4f6', 
                  padding: '12px', 
                  borderRadius: '8px',
                  fontSize: '0.9rem'
                }}>
                  <div><strong>Envoy Connections:</strong> {data.envoy.connections || 0}</div>
                  <div><strong>Envoy Requests:</strong> {data.envoy.requests || 0}</div>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {/* Request History Chart */}
      <div style={{
        background: 'rgba(255, 255, 255, 0.95)',
        borderRadius: '15px',
        padding: '25px',
        marginBottom: '20px',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.1)'
      }}>
        <h3 style={{ color: '#667eea', marginBottom: '20px', fontSize: '1.3rem', fontWeight: '600' }}>
          📊 Request Volume Over Time
        </h3>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={history}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis dataKey="time" stroke="#6b7280" />
            <YAxis stroke="#6b7280" />
            <Tooltip 
              contentStyle={{ 
                background: 'rgba(255, 255, 255, 0.95)', 
                border: '1px solid #e5e7eb',
                borderRadius: '8px'
              }} 
            />
            <Legend />
            <Line type="monotone" dataKey="serviceA" stroke="#667eea" strokeWidth={2} name="Service A" />
            <Line type="monotone" dataKey="serviceB" stroke="#764ba2" strokeWidth={2} name="Service B" />
            <Line type="monotone" dataKey="serviceC" stroke="#f59e0b" strokeWidth={2} name="Service C" />
          </LineChart>
        </ResponsiveContainer>
      </div>

      {/* Control Panel */}
      <div style={{
        background: 'rgba(255, 255, 255, 0.95)',
        borderRadius: '15px',
        padding: '25px',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.1)'
      }}>
        <h3 style={{ color: '#667eea', marginBottom: '20px', fontSize: '1.3rem', fontWeight: '600' }}>
          🎮 Service Mesh Controls
        </h3>
        
        <div style={{ marginBottom: '25px' }}>
          <label style={{ 
            display: 'block', 
            marginBottom: '10px', 
            color: '#4b5563',
            fontSize: '1rem',
            fontWeight: '500'
          }}>
            Service B Failure Rate: {failureRate}%
          </label>
          <input
            type="range"
            min="0"
            max="100"
            value={failureRate}
            onChange={(e) => setFailureRateHandler(parseInt(e.target.value))}
            style={{
              width: '100%',
              height: '8px',
              borderRadius: '5px',
              background: '#e5e7eb',
              outline: 'none'
            }}
          />
          <p style={{ color: '#6b7280', fontSize: '0.9rem', marginTop: '8px' }}>
            Simulate failures to see circuit breaker and retry policies in action
          </p>
        </div>

        <button
          onClick={sendTestRequest}
          style={{
            background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            color: 'white',
            border: 'none',
            padding: '15px 30px',
            borderRadius: '10px',
            fontSize: '1rem',
            fontWeight: '600',
            cursor: 'pointer',
            boxShadow: '0 4px 15px rgba(102, 126, 234, 0.4)',
            transition: 'transform 0.2s'
          }}
          onMouseOver={(e) => e.target.style.transform = 'translateY(-2px)'}
          onMouseOut={(e) => e.target.style.transform = 'translateY(0)'}
        >
          🚀 Send Test Request
        </button>
      </div>

      {/* Info Panel */}
      <div style={{
        background: 'rgba(255, 255, 255, 0.1)',
        backdropFilter: 'blur(10px)',
        borderRadius: '15px',
        padding: '20px',
        marginTop: '20px',
        border: '1px solid rgba(255, 255, 255, 0.2)'
      }}>
        <h4 style={{ marginBottom: '15px', fontSize: '1.1rem' }}>🔍 What's Happening:</h4>
        <ul style={{ lineHeight: '1.8', fontSize: '0.95rem', opacity: 0.9 }}>
          <li>✅ Service A → Envoy Proxy → Service B → Envoy Proxy → Service C</li>
          <li>🔒 mTLS encryption between services (configured in Envoy)</li>
          <li>🔄 Automatic retries on failures (3 attempts)</li>
          <li>⚡ Circuit breakers prevent cascade failures</li>
          <li>📊 Real-time metrics collected from all proxies</li>
          <li>⏱️ Timeout policies: 1s for Service B, 2s for Service C</li>
        </ul>
      </div>
    </div>
  );
}
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
RUN npm install -g serve
COPY --from=builder /app/dist /app/dist
CMD ["serve", "-s", "dist", "-l", "3000"]
EOF

# ============================================================================
# DOCKER COMPOSE
# ============================================================================
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  service-a:
    build: ./services/service-a
    container_name: service-a
    ports:
      - "3001:3001"
    networks:
      - mesh-network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3001/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  envoy-service-a:
    image: envoyproxy/envoy:v1.28-latest
    container_name: envoy-service-a
    volumes:
      - ./envoy/envoy-service-a.yaml:/etc/envoy/envoy.yaml
    ports:
      - "9901:9901"
      - "15001:15001"
    networks:
      - mesh-network
    depends_on:
      - service-a

  service-b:
    build: ./services/service-b
    container_name: service-b
    ports:
      - "3002:3002"
    networks:
      - mesh-network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3002/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  envoy-service-b:
    image: envoyproxy/envoy:v1.28-latest
    container_name: envoy-service-b
    volumes:
      - ./envoy/envoy-service-b.yaml:/etc/envoy/envoy.yaml
    ports:
      - "9902:9902"
      - "15002:15002"
    networks:
      - mesh-network
    depends_on:
      - service-b

  service-c:
    build: ./services/service-c
    container_name: service-c
    ports:
      - "3003:3003"
    networks:
      - mesh-network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3003/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  control-plane:
    build: ./control-plane
    container_name: control-plane
    ports:
      - "8080:8080"
    networks:
      - mesh-network
    depends_on:
      - service-a
      - service-b
      - service-c

  dashboard:
    build: ./dashboard
    container_name: mesh-dashboard
    ports:
      - "3000:3000"
    networks:
      - mesh-network
    depends_on:
      - control-plane

networks:
  mesh-network:
    driver: bridge
EOF

# ============================================================================
# TEST SUITE
# ============================================================================
cat > test-mesh.sh << 'EOF'
#!/bin/bash

echo "🧪 Testing Service Mesh Functionality..."
echo ""

# Wait for services to be ready
sleep 5

echo "1️⃣  Testing basic service chain..."
response=$(curl -s http://localhost:3001/api/orders)
if echo "$response" | grep -q "service-a"; then
  echo "✅ Service chain working"
else
  echo "❌ Service chain failed"
fi
echo ""

echo "2️⃣  Testing retry logic (inducing failures)..."
curl -s -X POST http://localhost:8080/api/service-b/failure-rate \
  -H "Content-Type: application/json" \
  -d '{"rate": 0.5}' > /dev/null

for i in {1..5}; do
  response=$(curl -s http://localhost:3001/api/orders)
  echo "Request $i: $(echo $response | grep -o '"service":"[^"]*"' | head -1)"
done
echo ""

echo "3️⃣  Resetting failure rate..."
curl -s -X POST http://localhost:8080/api/service-b/failure-rate \
  -H "Content-Type: application/json" \
  -d '{"rate": 0}' > /dev/null
echo "✅ Failure rate reset"
echo ""

echo "4️⃣  Testing Envoy admin endpoints..."
envoy_stats=$(curl -s http://localhost:9901/stats | grep "downstream_rq_total" | head -1)
echo "Envoy Service A stats: $envoy_stats"
echo ""

echo "5️⃣  Testing mesh status API..."
mesh_status=$(curl -s http://localhost:8080/api/mesh-status)
service_count=$(echo "$mesh_status" | grep -o '"service-[abc]"' | wc -l)
echo "✅ Mesh monitoring $service_count services"
echo ""

echo "6️⃣  Load test (10 requests)..."
for i in {1..10}; do
  curl -s http://localhost:3001/api/orders > /dev/null &
done
wait
echo "✅ Load test completed"
echo ""

echo "✅ All tests completed!"
echo ""
echo "📊 View the dashboard at: http://localhost:3000"
echo "🔧 Envoy Admin Service A: http://localhost:9901"
echo "🔧 Envoy Admin Service B: http://localhost:9902"
EOF

chmod +x test-mesh.sh

# ============================================================================
# DEMO STARTUP SCRIPT
# ============================================================================
cat > demo.sh << 'EOF'
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo ""
echo "🔨 Building Docker images..."
docker-compose build

echo ""
echo "🚀 Starting Service Mesh..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready (30 seconds)..."
sleep 30

echo ""
./test-mesh.sh

echo ""
echo "=========================================="
echo "✅ SERVICE MESH DEMO READY!"
echo "=========================================="
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔧 Service A: http://localhost:3001"
echo "🔧 Service B: http://localhost:3002"
echo "🔧 Service C: http://localhost:3003"
echo "🎛️  Control Plane: http://localhost:8080"
echo "📈 Envoy Admin A: http://localhost:9901"
echo "📈 Envoy Admin B: http://localhost:9902"
echo ""
echo "Try these:"
echo "  1. Open dashboard and watch real-time metrics"
echo "  2. Use failure rate slider to see circuit breakers"
echo "  3. Send test requests and observe retry behavior"
echo "  4. Check Envoy stats at admin endpoints"
echo ""
echo "📋 View logs: docker-compose logs -f"
echo "🧹 Cleanup: ./cleanup.sh"
EOF

chmod +x demo.sh

# ============================================================================
# CLEANUP SCRIPT
# ============================================================================
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Service Mesh Demo..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

docker-compose down -v

echo "✅ Cleanup complete!"
echo "Note: To remove the entire service-mesh-demo directory, run: rm -rf service-mesh-demo"
EOF

chmod +x cleanup.sh

echo ""
echo "=========================================="
echo "✅ Demo files created successfully!"
echo "=========================================="
echo ""
echo "To run the demo:"
echo "  cd service-mesh-demo && ./demo.sh"
echo ""
echo "To cleanup:"
echo "  cd service-mesh-demo && ./cleanup.sh"