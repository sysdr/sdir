#!/bin/bash

set -e

echo "=================================================="
echo "Issue #168: Observability from Day One Demo"
echo "=================================================="
echo ""

# Create project structure
echo "📁 Creating project structure..."
mkdir -p observability-demo/{api-gateway,payment-service,inventory-service,dashboard,tests}
mkdir -p observability-demo/dashboard/{public,src}

# Create Docker Compose
echo "🐳 Creating Docker Compose configuration..."
cat > observability-demo/docker-compose.yml << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.47.0
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    networks:
      - obs-net

  api-gateway:
    build: ./api-gateway
    container_name: api-gateway
    ports:
      - "3000:3000"
    environment:
      - PAYMENT_SERVICE_URL=http://payment-service:3001
      - INVENTORY_SERVICE_URL=http://inventory-service:3002
    depends_on:
      - payment-service
      - inventory-service
    networks:
      - obs-net

  payment-service:
    build: ./payment-service
    container_name: payment-service
    ports:
      - "3001:3001"
    networks:
      - obs-net

  inventory-service:
    build: ./inventory-service
    container_name: inventory-service
    ports:
      - "3002:3002"
    networks:
      - obs-net

  dashboard:
    build: ./dashboard
    container_name: dashboard
    ports:
      - "3003:80"
    depends_on:
      - api-gateway
    networks:
      - obs-net

networks:
  obs-net:
    driver: bridge
EOF

# Create Prometheus config
cat > observability-demo/prometheus.yml << 'EOF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'api-gateway'
    static_configs:
      - targets: ['api-gateway:3000']
  
  - job_name: 'payment-service'
    static_configs:
      - targets: ['payment-service:3001']
  
  - job_name: 'inventory-service'
    static_configs:
      - targets: ['inventory-service:3002']
EOF

# API Gateway Service
echo "🚪 Creating API Gateway service..."
cat > observability-demo/api-gateway/package.json << 'EOF'
{
  "name": "api-gateway",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "prom-client": "^15.0.0",
    "uuid": "^9.0.1",
    "winston": "^3.11.0"
  }
}
EOF

cat > observability-demo/api-gateway/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const winston = require('winston');
const promClient = require('prom-client');

const app = express();
const PORT = 3000;

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'status'],
  buckets: [10, 50, 100, 200, 500, 1000, 2000]
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status']
});

register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);

// Structured logging
const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

// CORS middleware
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Trace-ID, X-Span-ID, X-Parent-Span-ID');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// Middleware for tracing
app.use(express.json());
app.use((req, res, next) => {
  req.traceId = req.headers['x-trace-id'] || uuidv4();
  req.spanId = uuidv4();
  req.startTime = Date.now();
  
  res.setHeader('X-Trace-ID', req.traceId);
  res.setHeader('X-Span-ID', req.spanId);
  
  next();
});

// Logging middleware
app.use((req, res, next) => {
  const originalSend = res.send;
  res.send = function(data) {
    const duration = Date.now() - req.startTime;
    
    logger.info({
      service: 'api-gateway',
      traceId: req.traceId,
      spanId: req.spanId,
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration,
      level: res.statusCode >= 400 ? 'error' : 'info'
    });
    
    httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
    httpRequestTotal.labels(req.method, req.path, res.statusCode).inc();
    
    originalSend.call(this, data);
  };
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'api-gateway' });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Process order endpoint
app.post('/api/orders', async (req, res) => {
  const childSpanId = uuidv4();
  const { userId, productId, amount } = req.body;
  
  logger.info({
    service: 'api-gateway',
    traceId: req.traceId,
    spanId: req.spanId,
    event: 'order_received',
    userId,
    productId,
    amount
  });

  try {
    // Call payment service
    const paymentResponse = await axios.post(
      `${process.env.PAYMENT_SERVICE_URL}/api/charge`,
      { userId, amount },
      {
        headers: {
          'X-Trace-ID': req.traceId,
          'X-Parent-Span-ID': req.spanId,
          'X-Span-ID': childSpanId
        }
      }
    );

    // Call inventory service
    const inventoryResponse = await axios.post(
      `${process.env.INVENTORY_SERVICE_URL}/api/reserve`,
      { productId, quantity: 1 },
      {
        headers: {
          'X-Trace-ID': req.traceId,
          'X-Parent-Span-ID': req.spanId,
          'X-Span-ID': uuidv4()
        }
      }
    );

    logger.info({
      service: 'api-gateway',
      traceId: req.traceId,
      spanId: req.spanId,
      event: 'order_completed',
      paymentStatus: paymentResponse.data.status,
      inventoryStatus: inventoryResponse.data.status
    });

    res.json({
      success: true,
      orderId: uuidv4(),
      traceId: req.traceId,
      payment: paymentResponse.data,
      inventory: inventoryResponse.data
    });
  } catch (error) {
    logger.error({
      service: 'api-gateway',
      traceId: req.traceId,
      spanId: req.spanId,
      event: 'order_failed',
      error: error.message
    });
    
    res.status(500).json({
      success: false,
      error: error.message,
      traceId: req.traceId
    });
  }
});

// Get telemetry data
app.get('/api/telemetry', async (req, res) => {
  try {
    const metrics = await register.metrics();
    res.json({
      logs: 'Check console for structured logs',
      metrics: metrics,
      tracing: 'Headers propagated across services'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Prometheus query proxy (to avoid CORS issues)
app.get('/api/prometheus/query', async (req, res) => {
  try {
    const query = req.query.query;
    if (!query) {
      return res.status(400).json({ error: 'Query parameter required' });
    }
    const prometheusUrl = process.env.PROMETHEUS_URL || 'http://prometheus:9090';
    const response = await axios.get(\`\${prometheusUrl}/api/v1/query\`, {
      params: { query }
    });
    res.json(response.data);
  } catch (error) {
    logger.error({
      service: 'api-gateway',
      event: 'prometheus_query_failed',
      error: error.message
    });
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  logger.info({
    service: 'api-gateway',
    event: 'server_started',
    port: PORT
  });
  console.log(`API Gateway running on port ${PORT}`);
});
EOF

cat > observability-demo/api-gateway/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# Payment Service
echo "💳 Creating Payment service..."
cat > observability-demo/payment-service/package.json << 'EOF'
{
  "name": "payment-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.0.0",
    "uuid": "^9.0.1",
    "winston": "^3.11.0"
  }
}
EOF

cat > observability-demo/payment-service/server.js << 'EOF'
const express = require('express');
const winston = require('winston');
const promClient = require('prom-client');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = 3001;

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const paymentDuration = new promClient.Histogram({
  name: 'payment_processing_duration_ms',
  help: 'Payment processing duration',
  labelNames: ['status'],
  buckets: [50, 100, 200, 500, 1000]
});

const paymentsTotal = new promClient.Counter({
  name: 'payments_total',
  help: 'Total payments processed',
  labelNames: ['status']
});

register.registerMetric(paymentDuration);
register.registerMetric(paymentsTotal);

// Structured logging
const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

app.use(express.json());

// Trace context middleware
app.use((req, res, next) => {
  req.traceId = req.headers['x-trace-id'] || uuidv4();
  req.parentSpanId = req.headers['x-parent-span-id'];
  req.spanId = req.headers['x-span-id'] || uuidv4();
  
  res.setHeader('X-Trace-ID', req.traceId);
  res.setHeader('X-Span-ID', req.spanId);
  
  next();
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment-service' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.post('/api/charge', async (req, res) => {
  const startTime = Date.now();
  const { userId, amount } = req.body;
  
  logger.info({
    service: 'payment-service',
    traceId: req.traceId,
    spanId: req.spanId,
    parentSpanId: req.parentSpanId,
    event: 'payment_started',
    userId,
    amount
  });

  // Simulate payment processing with variable latency
  const processingTime = Math.random() * 300 + 100;
  await new Promise(resolve => setTimeout(resolve, processingTime));

  // Simulate 10% failure rate
  const success = Math.random() > 0.1;
  const duration = Date.now() - startTime;
  const status = success ? 'success' : 'failed';

  logger.info({
    service: 'payment-service',
    traceId: req.traceId,
    spanId: req.spanId,
    parentSpanId: req.parentSpanId,
    event: 'payment_completed',
    status,
    duration,
    amount
  });

  paymentDuration.labels(status).observe(duration);
  paymentsTotal.labels(status).inc();

  if (success) {
    res.json({
      status: 'success',
      transactionId: uuidv4(),
      amount,
      traceId: req.traceId,
      duration
    });
  } else {
    res.status(500).json({
      status: 'failed',
      error: 'Payment processing failed',
      traceId: req.traceId
    });
  }
});

app.listen(PORT, () => {
  logger.info({
    service: 'payment-service',
    event: 'server_started',
    port: PORT
  });
  console.log(`Payment Service running on port ${PORT}`);
});
EOF

cat > observability-demo/payment-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY . .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

# Inventory Service
echo "📦 Creating Inventory service..."
cat > observability-demo/inventory-service/package.json << 'EOF'
{
  "name": "inventory-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.0.0",
    "uuid": "^9.0.1",
    "winston": "^3.11.0"
  }
}
EOF

cat > observability-demo/inventory-service/server.js << 'EOF'
const express = require('express');
const winston = require('winston');
const promClient = require('prom-client');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = 3002;

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const inventoryChecks = new promClient.Counter({
  name: 'inventory_checks_total',
  help: 'Total inventory checks',
  labelNames: ['status']
});

const inventoryLatency = new promClient.Histogram({
  name: 'inventory_check_duration_ms',
  help: 'Inventory check duration',
  labelNames: ['status'],
  buckets: [10, 25, 50, 100, 250, 500]
});

register.registerMetric(inventoryChecks);
register.registerMetric(inventoryLatency);

// Structured logging
const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

app.use(express.json());

// Trace context middleware
app.use((req, res, next) => {
  req.traceId = req.headers['x-trace-id'] || uuidv4();
  req.parentSpanId = req.headers['x-parent-span-id'];
  req.spanId = req.headers['x-span-id'] || uuidv4();
  
  res.setHeader('X-Trace-ID', req.traceId);
  res.setHeader('X-Span-ID', req.spanId);
  
  next();
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'inventory-service' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.post('/api/reserve', async (req, res) => {
  const startTime = Date.now();
  const { productId, quantity } = req.body;
  
  logger.info({
    service: 'inventory-service',
    traceId: req.traceId,
    spanId: req.spanId,
    parentSpanId: req.parentSpanId,
    event: 'reservation_started',
    productId,
    quantity
  });

  // Simulate database query
  const queryTime = Math.random() * 150 + 50;
  await new Promise(resolve => setTimeout(resolve, queryTime));

  // Simulate 5% out-of-stock scenarios
  const available = Math.random() > 0.05;
  const duration = Date.now() - startTime;
  const status = available ? 'reserved' : 'out_of_stock';

  logger.info({
    service: 'inventory-service',
    traceId: req.traceId,
    spanId: req.spanId,
    parentSpanId: req.parentSpanId,
    event: 'reservation_completed',
    status,
    duration,
    productId
  });

  inventoryLatency.labels(status).observe(duration);
  inventoryChecks.labels(status).inc();

  if (available) {
    res.json({
      status: 'reserved',
      reservationId: uuidv4(),
      productId,
      quantity,
      traceId: req.traceId,
      duration
    });
  } else {
    res.status(409).json({
      status: 'out_of_stock',
      productId,
      traceId: req.traceId
    });
  }
});

app.listen(PORT, () => {
  logger.info({
    service: 'inventory-service',
    event: 'server_started',
    port: PORT
  });
  console.log(`Inventory Service running on port ${PORT}`);
});
EOF

cat > observability-demo/inventory-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY . .
EXPOSE 3002
CMD ["node", "server.js"]
EOF

# Dashboard
echo "📊 Creating React Dashboard..."
cat > observability-demo/dashboard/package.json << 'EOF'
{
  "name": "observability-dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "axios": "^1.6.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "eslintConfig": {
    "extends": ["react-app"]
  },
  "browserslist": {
    "production": [">0.2%", "not dead"],
    "development": ["last 1 chrome version"]
  }
}
EOF

cat > observability-demo/dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Observability Dashboard</title>
</head>
<body>
  <div id="root"></div>
</body>
</html>
EOF

cat > observability-demo/dashboard/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
EOF

cat > observability-demo/dashboard/src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

function App() {
  const [logs, setLogs] = useState([]);
  const [metrics, setMetrics] = useState({ requests: 0, errors: 0, avgLatency: 0 });
  const [loading, setLoading] = useState(false);
  const [lastTraceId, setLastTraceId] = useState('');

  const processOrder = async () => {
    setLoading(true);
    try {
      const response = await axios.post('http://localhost:3000/api/orders', {
        userId: `user-${Math.floor(Math.random() * 1000)}`,
        productId: `prod-${Math.floor(Math.random() * 100)}`,
        amount: Math.floor(Math.random() * 500) + 50
      });
      
      const newLog = {
        timestamp: new Date().toISOString(),
        traceId: response.data.traceId,
        event: 'order_created',
        status: 'success',
        service: 'api-gateway'
      };
      
      setLogs(prev => [newLog, ...prev].slice(0, 20));
      setLastTraceId(response.data.traceId);
      // Wait a bit for metrics to be scraped
      setTimeout(() => updateMetrics(), 2000);
    } catch (error) {
      const errorLog = {
        timestamp: new Date().toISOString(),
        traceId: error.response?.data?.traceId || 'N/A',
        event: 'order_failed',
        status: 'error',
        service: 'api-gateway',
        error: error.message
      };
      setLogs(prev => [errorLog, ...prev].slice(0, 20));
      // Wait a bit for metrics to be scraped
      setTimeout(() => updateMetrics(), 2000);
    }
    setLoading(false);
  };

  const updateMetrics = async () => {
    try {
      // Fetch total requests
      const requestsRes = await axios.get('http://localhost:9090/api/v1/query?query=sum(http_requests_total)');
      const totalRequests = requestsRes.data?.data?.result?.[0]?.value?.[1] || '0';
      
      // Fetch error requests
      const errorRes = await axios.get('http://localhost:9090/api/v1/query?query=sum(http_requests_total{status=~"5.."})');
      const totalErrors = errorRes.data?.data?.result?.[0]?.value?.[1] || '0';
      
      // Fetch average latency
      const latencyRes = await axios.get('http://localhost:9090/api/v1/query?query=rate(http_request_duration_ms_sum[5m])/rate(http_request_duration_ms_count[5m])*1000');
      const avgLatency = latencyRes.data?.data?.result?.[0]?.value?.[1] || '0';
      
      setMetrics({
        requests: parseInt(totalRequests) || 0,
        errors: parseInt(totalErrors) || 0,
        avgLatency: Math.round(parseFloat(avgLatency)) || 0
      });
    } catch (error) {
      console.error('Failed to fetch metrics:', error);
      // Keep previous metrics on error
    }
  };

  useEffect(() => {
    // Initial metrics fetch
    updateMetrics();
    // Update metrics every 5 seconds
    const interval = setInterval(() => {
      updateMetrics();
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="App">
      <header className="header">
        <h1>🔭 Observability Dashboard</h1>
        <p>Real-time Logs, Metrics & Traces</p>
      </header>

      <div className="container">
        <div className="metrics-grid">
          <div className="metric-card">
            <div className="metric-label">Total Requests</div>
            <div className="metric-value">{metrics.requests}</div>
          </div>
          <div className="metric-card">
            <div className="metric-label">Error Rate</div>
            <div className="metric-value">
              {metrics.requests > 0 ? ((metrics.errors / metrics.requests) * 100).toFixed(1) : 0}%
            </div>
          </div>
          <div className="metric-card">
            <div className="metric-label">Avg Latency</div>
            <div className="metric-value">{metrics.avgLatency}ms</div>
          </div>
        </div>

        <div className="actions">
          <button 
            className="action-button" 
            onClick={processOrder}
            disabled={loading}
          >
            {loading ? '⏳ Processing...' : '🚀 Create Order'}
          </button>
          {lastTraceId && (
            <div className="trace-id">
              Last Trace ID: <code>{lastTraceId}</code>
            </div>
          )}
        </div>

        <div className="section">
          <h2>📋 Structured Logs</h2>
          <div className="logs-container">
            {logs.length === 0 ? (
              <div className="empty-state">No logs yet. Create an order to see structured logs.</div>
            ) : (
              logs.map((log, index) => (
                <div key={index} className={`log-entry ${log.status}`}>
                  <span className="log-timestamp">{new Date(log.timestamp).toLocaleTimeString()}</span>
                  <span className="log-service">{log.service}</span>
                  <span className="log-event">{log.event}</span>
                  <span className="log-trace">Trace: {log.traceId.substring(0, 8)}...</span>
                  {log.error && <span className="log-error">{log.error}</span>}
                </div>
              ))
            )}
          </div>
        </div>

        <div className="section">
          <h2>📊 Metrics</h2>
          <div className="metrics-info">
            <p>✅ Prometheus collecting metrics at <a href="http://localhost:9090" target="_blank" rel="noopener noreferrer">localhost:9090</a></p>
            <p>✅ Service metrics available at:</p>
            <ul>
              <li><a href="http://localhost:3000/metrics" target="_blank" rel="noopener noreferrer">API Gateway Metrics</a></li>
              <li><a href="http://localhost:3001/metrics" target="_blank" rel="noopener noreferrer">Payment Service Metrics</a></li>
              <li><a href="http://localhost:3002/metrics" target="_blank" rel="noopener noreferrer">Inventory Service Metrics</a></li>
            </ul>
          </div>
        </div>

        <div className="section">
          <h2>🔗 Distributed Tracing</h2>
          <div className="trace-info">
            <p>Trace IDs are automatically propagated across all services via HTTP headers:</p>
            <ul>
              <li><code>X-Trace-ID</code>: Unique identifier for the entire request</li>
              <li><code>X-Span-ID</code>: Unique identifier for each service span</li>
              <li><code>X-Parent-Span-ID</code>: Links spans in a causal chain</li>
            </ul>
            <p>Check service logs in Docker to see trace propagation in action!</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
EOF

cat > observability-demo/dashboard/src/App.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

.App {
  min-height: 100vh;
  padding: 20px;
}

.header {
  text-align: center;
  color: white;
  margin-bottom: 30px;
  padding: 30px 20px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 20px;
  backdrop-filter: blur(10px);
}

.header h1 {
  font-size: 2.5em;
  margin-bottom: 10px;
}

.header p {
  font-size: 1.2em;
  opacity: 0.9;
}

.container {
  max-width: 1200px;
  margin: 0 auto;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 20px;
  margin-bottom: 30px;
}

.metric-card {
  background: white;
  padding: 25px;
  border-radius: 15px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
  text-align: center;
}

.metric-label {
  font-size: 0.9em;
  color: #666;
  margin-bottom: 10px;
  text-transform: uppercase;
  letter-spacing: 1px;
}

.metric-value {
  font-size: 2.5em;
  font-weight: bold;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.actions {
  text-align: center;
  margin: 30px 0;
}

.action-button {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  padding: 15px 40px;
  font-size: 1.1em;
  border-radius: 50px;
  cursor: pointer;
  box-shadow: 0 10px 30px rgba(102, 126, 234, 0.4);
  transition: transform 0.2s, box-shadow 0.2s;
}

.action-button:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 15px 40px rgba(102, 126, 234, 0.6);
}

.action-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.trace-id {
  margin-top: 15px;
  color: white;
  font-size: 0.9em;
}

.trace-id code {
  background: rgba(255, 255, 255, 0.2);
  padding: 5px 10px;
  border-radius: 5px;
  font-family: monospace;
}

.section {
  background: white;
  padding: 25px;
  border-radius: 15px;
  margin-bottom: 20px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
}

.section h2 {
  color: #667eea;
  margin-bottom: 20px;
  font-size: 1.5em;
}

.logs-container {
  max-height: 400px;
  overflow-y: auto;
  background: #f8f9fa;
  border-radius: 10px;
  padding: 15px;
}

.log-entry {
  display: flex;
  align-items: center;
  gap: 15px;
  padding: 12px;
  margin-bottom: 8px;
  background: white;
  border-radius: 8px;
  border-left: 4px solid #667eea;
  font-size: 0.9em;
}

.log-entry.error {
  border-left-color: #e74c3c;
  background: #fee;
}

.log-timestamp {
  color: #666;
  font-family: monospace;
  font-size: 0.85em;
}

.log-service {
  background: #667eea;
  color: white;
  padding: 3px 10px;
  border-radius: 12px;
  font-size: 0.85em;
}

.log-event {
  font-weight: 600;
  color: #333;
}

.log-trace {
  font-family: monospace;
  color: #888;
  font-size: 0.85em;
}

.log-error {
  color: #e74c3c;
  font-weight: 500;
}

.empty-state {
  text-align: center;
  padding: 40px;
  color: #999;
  font-style: italic;
}

.metrics-info, .trace-info {
  line-height: 1.8;
  color: #555;
}

.metrics-info a, .trace-info a {
  color: #667eea;
  text-decoration: none;
  font-weight: 600;
}

.metrics-info a:hover, .trace-info a:hover {
  text-decoration: underline;
}

.metrics-info ul, .trace-info ul {
  margin-left: 20px;
  margin-top: 10px;
}

.trace-info code {
  background: #f0f0f0;
  padding: 2px 8px;
  border-radius: 4px;
  font-family: monospace;
  color: #667eea;
}
EOF

cat > observability-demo/dashboard/Dockerfile << 'EOF'
FROM node:18-alpine as build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

cat > observability-demo/dashboard/nginx.conf << 'EOF'
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri /index.html;
    }
}
EOF

# Create tests
echo "🧪 Creating test suite..."
cat > observability-demo/tests/test.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Observability Tests..."
echo ""

# Test 1: Health checks
echo "Test 1: Health checks..."
curl -s http://localhost:3000/health | grep -q "healthy" && echo "✅ API Gateway healthy" || echo "❌ API Gateway failed"
curl -s http://localhost:3001/health | grep -q "healthy" && echo "✅ Payment Service healthy" || echo "❌ Payment Service failed"
curl -s http://localhost:3002/health | grep -q "healthy" && echo "✅ Inventory Service healthy" || echo "❌ Inventory Service failed"

echo ""
echo "Test 2: Metrics endpoints..."
curl -s http://localhost:3000/metrics | grep -q "http_requests_total" && echo "✅ Gateway metrics available" || echo "❌ Gateway metrics failed"
curl -s http://localhost:3001/metrics | grep -q "payments_total" && echo "✅ Payment metrics available" || echo "❌ Payment metrics failed"

echo ""
echo "Test 3: Process order with trace ID..."
RESPONSE=$(curl -s -X POST http://localhost:3000/api/orders \
  -H "Content-Type: application/json" \
  -d '{"userId": "test-user", "productId": "test-product", "amount": 100}')

TRACE_ID=$(echo $RESPONSE | grep -o '"traceId":"[^"]*"' | cut -d'"' -f4)

if [ ! -z "$TRACE_ID" ]; then
  echo "✅ Order processed with trace ID: $TRACE_ID"
else
  echo "❌ No trace ID returned"
fi

echo ""
echo "Test 4: Verify structured logging..."
docker logs api-gateway 2>&1 | tail -5 | grep -q "traceId" && echo "✅ Structured logs with trace ID" || echo "❌ Structured logging failed"

echo ""
echo "Test 5: Prometheus metrics collection..."
curl -s http://localhost:9090/api/v1/query?query=up | grep -q '"value":\[.*,"1"\]' && echo "✅ Prometheus collecting metrics" || echo "❌ Prometheus failed"

echo ""
echo "✅ All tests completed!"
EOF

chmod +x observability-demo/tests/test.sh

# Build and run
echo ""
echo "🏗️  Building services..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/observability-demo" || { echo "❌ Failed to change to observability-demo directory"; exit 1; }
docker-compose build --parallel

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 15

echo ""
echo "🧪 Running tests..."
if [ -f "./tests/test.sh" ]; then
  bash ./tests/test.sh
else
  echo "❌ Test script not found at ./tests/test.sh"
  exit 1
fi

echo ""
echo "=================================================="
echo "✅ Observability Demo is Ready!"
echo "=================================================="
echo ""
echo "🌐 Access Points:"
echo "   Dashboard:        http://localhost:3003"
echo "   API Gateway:      http://localhost:3000"
echo "   Prometheus:       http://localhost:9090"
echo ""
echo "📊 Try it out:"
echo "   1. Open the dashboard at http://localhost:3003"
echo "   2. Click 'Create Order' to generate traffic"
echo "   3. Watch logs, metrics, and traces in real-time"
echo "   4. Check service logs: docker logs -f api-gateway"
echo "   5. Query Prometheus: http://localhost:9090"
echo ""
echo "🔍 Observe:"
echo "   • Structured JSON logs with trace IDs"
echo "   • Metrics with dimensional labels"
echo "   • Trace context propagation across services"
echo "   • Real-time latency and error tracking"
echo ""
echo "Run './cleanup.sh' to stop and clean up everything"
echo "=================================================="

# Create cleanup script
echo "🧹 Creating cleanup script..."
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Observability Demo..."

cd observability-demo 2>/dev/null

if [ -f docker-compose.yml ]; then
  echo "Stopping containers..."
  docker-compose down -v
  
  echo "Removing images..."
  docker-compose down --rmi local
fi

cd ..

echo "Removing project files..."
rm -rf observability-demo

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

echo ""
echo "=================================================="
echo "✅ All files created successfully!"
echo "=================================================="
echo ""
echo "📁 Created files:"
echo "   • article.md - Complete lesson article"
echo "   • diagram1-three-pillars.svg - Architecture diagram"
echo "   • diagram2-trace-propagation.svg - Trace flow diagram"
echo "   • demo.sh - One-click demo script"
echo "   • cleanup.sh - Cleanup script"
echo ""
echo "🚀 To run the demo:"
echo "   ./demo.sh"
echo ""
echo "🧹 To cleanup:"
echo "   ./cleanup.sh"
echo "=================================================="