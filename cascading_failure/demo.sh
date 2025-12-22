#!/bin/bash

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Cascading Timeouts Demo - System Design Interview Roadmap   ║"
echo "║                                                                ║"
echo "║  This demo shows how a slow service creates a cascade of      ║"
echo "║  timeouts that propagates through your entire system.         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "✅ Docker found"
echo ""

# Create project structure
echo "📁 Creating project structure..."
mkdir -p cascading-timeouts-demo
cd cascading-timeouts-demo

# Create directories
mkdir -p service-a service-b service-c dashboard load-generator

# Create Service C (Database/External API simulator)
echo "🔧 Creating Service C (Database Layer)..."
cat > service-c/package.json << 'EOF'
{
  "name": "service-c",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.1.0"
  }
}
EOF

cat > service-c/server.js << 'EOF'
const express = require('express');
const client = require('prom-client');

const app = express();
const PORT = 3003;

// Prometheus metrics
const register = new client.Registry();
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

let artificialDelay = 0;
let requestCount = 0;
let errorCount = 0;

app.use(express.json());

// Middleware to track metrics
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
  });
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'service-c', delay: artificialDelay });
});

// Main data endpoint
app.get('/data', async (req, res) => {
  requestCount++;
  
  // Simulate processing with artificial delay
  if (artificialDelay > 0) {
    await new Promise(resolve => setTimeout(resolve, artificialDelay));
  } else {
    // Normal operation: 50-100ms
    await new Promise(resolve => setTimeout(resolve, Math.random() * 50 + 50));
  }
  
  res.json({ 
    data: 'Database query result',
    service: 'service-c',
    timestamp: new Date().toISOString(),
    processingTime: artificialDelay || 'normal'
  });
});

// Control endpoint to inject delay
app.post('/control/delay', (req, res) => {
  const { delay } = req.body;
  artificialDelay = delay;
  console.log(`🐌 Artificial delay set to ${delay}ms`);
  res.json({ message: `Delay set to ${delay}ms`, currentDelay: artificialDelay });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.send(metrics);
});

// Status endpoint
app.get('/status', (req, res) => {
  res.json({
    service: 'service-c',
    requestCount,
    errorCount,
    artificialDelay,
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(`✅ Service C (Database) running on port ${PORT}`);
  console.log(`   Normal latency: 50-100ms`);
});
EOF

cat > service-c/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3003
CMD ["node", "server.js"]
EOF

# Create Service B (Business Logic)
echo "🔧 Creating Service B (Business Logic Layer)..."
cat > service-b/package.json << 'EOF'
{
  "name": "service-b",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "prom-client": "^15.1.0"
  }
}
EOF

cat > service-b/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const client = require('prom-client');

const app = express();
const PORT = 3002;

// Prometheus metrics
const register = new client.Registry();
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

let requestCount = 0;
let errorCount = 0;
let timeoutCount = 0;
let activeRequests = 0;
const MAX_CONCURRENT = 50;

app.use(express.json());

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
  });
  next();
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'service-b',
    activeRequests,
    maxConcurrent: MAX_CONCURRENT
  });
});

// Business logic endpoint that calls Service C
app.get('/process', async (req, res) => {
  requestCount++;
  activeRequests++;
  
  // Check if we're overloaded
  if (activeRequests > MAX_CONCURRENT) {
    activeRequests--;
    return res.status(503).json({ error: 'Service overloaded', activeRequests });
  }
  
  try {
    const start = Date.now();
    
    // Call Service C with 2 second timeout
    const response = await axios.get('http://service-c:3003/data', {
      timeout: 2000
    });
    
    const duration = Date.now() - start;
    
    // Add some business logic processing
    await new Promise(resolve => setTimeout(resolve, 50));
    
    activeRequests--;
    res.json({
      result: 'Business logic processed',
      service: 'service-b',
      downstreamData: response.data,
      processingTime: duration,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    activeRequests--;
    errorCount++;
    
    if (error.code === 'ECONNABORTED') {
      timeoutCount++;
      console.log(`⏱️ Timeout calling Service C (${timeoutCount} total timeouts)`);
      return res.status(504).json({ 
        error: 'Timeout calling downstream service',
        message: 'Service C is too slow',
        timeoutCount
      });
    }
    
    console.error('Error calling Service C:', error.message);
    res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.send(metrics);
});

app.get('/status', (req, res) => {
  res.json({
    service: 'service-b',
    requestCount,
    errorCount,
    timeoutCount,
    activeRequests,
    maxConcurrent: MAX_CONCURRENT,
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(`✅ Service B (Business Logic) running on port ${PORT}`);
  console.log(`   Timeout for Service C calls: 2 seconds`);
  console.log(`   Max concurrent requests: ${MAX_CONCURRENT}`);
});
EOF

cat > service-b/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3002
CMD ["node", "server.js"]
EOF

# Create Service A (API Gateway)
echo "🔧 Creating Service A (API Gateway)..."
cat > service-a/package.json << 'EOF'
{
  "name": "service-a",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "prom-client": "^15.1.0"
  }
}
EOF

cat > service-a/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const client = require('prom-client');

const app = express();
const PORT = 3001;

// Prometheus metrics
const register = new client.Registry();
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

let requestCount = 0;
let errorCount = 0;
let timeoutCount = 0;
let activeRequests = 0;
const MAX_CONCURRENT = 100;

app.use(express.json());

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
  });
  next();
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'service-a',
    activeRequests,
    maxConcurrent: MAX_CONCURRENT
  });
});

// API endpoint that calls Service B
app.get('/api/data', async (req, res) => {
  requestCount++;
  activeRequests++;
  
  // Check if we're overloaded
  if (activeRequests > MAX_CONCURRENT) {
    activeRequests--;
    return res.status(503).json({ error: 'API Gateway overloaded', activeRequests });
  }
  
  try {
    const start = Date.now();
    
    // Call Service B with 3 second timeout
    const response = await axios.get('http://service-b:3002/process', {
      timeout: 3000
    });
    
    const duration = Date.now() - start;
    
    // Add some gateway logic
    await new Promise(resolve => setTimeout(resolve, 20));
    
    activeRequests--;
    res.json({
      success: true,
      service: 'service-a',
      data: response.data,
      totalTime: duration,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    activeRequests--;
    errorCount++;
    
    if (error.code === 'ECONNABORTED') {
      timeoutCount++;
      console.log(`⏱️ Timeout calling Service B (${timeoutCount} total timeouts)`);
      return res.status(504).json({ 
        error: 'Gateway timeout',
        message: 'Downstream services are too slow',
        timeoutCount
      });
    }
    
    if (error.response && error.response.status === 504) {
      timeoutCount++;
      console.log(`⏱️ Downstream timeout propagated (${timeoutCount} total)`);
      return res.status(504).json({
        error: 'Cascading timeout',
        message: 'Service B timed out calling Service C',
        timeoutCount
      });
    }
    
    console.error('Error calling Service B:', error.message);
    res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

// Control endpoint to trigger delay in Service C
app.post('/control/slow', async (req, res) => {
  try {
    const { delay } = req.body;
    await axios.post('http://service-c:3003/control/delay', { delay });
    res.json({ message: `Service C delay set to ${delay}ms` });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.send(metrics);
});

app.get('/status', (req, res) => {
  res.json({
    service: 'service-a',
    requestCount,
    errorCount,
    timeoutCount,
    activeRequests,
    maxConcurrent: MAX_CONCURRENT,
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(`✅ Service A (API Gateway) running on port ${PORT}`);
  console.log(`   Timeout for Service B calls: 3 seconds`);
  console.log(`   Max concurrent requests: ${MAX_CONCURRENT}`);
});
EOF

cat > service-a/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

# Create Dashboard
echo "🔧 Creating Web Dashboard..."
cat > dashboard/package.json << 'EOF'
{
  "name": "dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0"
  }
}
EOF

cat > dashboard/server.js << 'EOF'
const express = require('express');
const path = require('path');
const axios = require('axios');

const app = express();
const PORT = 3000;

app.use(express.json());
app.use(express.static('public'));

// Proxy endpoint to get status from all services
app.get('/api/status', async (req, res) => {
  try {
    const [serviceA, serviceB, serviceC] = await Promise.allSettled([
      axios.get('http://service-a:3001/status', { timeout: 1000 }),
      axios.get('http://service-b:3002/status', { timeout: 1000 }),
      axios.get('http://service-c:3003/status', { timeout: 1000 })
    ]);

    res.json({
      serviceA: serviceA.status === 'fulfilled' ? serviceA.value.data : { error: 'Timeout' },
      serviceB: serviceB.status === 'fulfilled' ? serviceB.value.data : { error: 'Timeout' },
      serviceC: serviceC.status === 'fulfilled' ? serviceC.value.data : { error: 'Timeout' },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Control endpoint
app.post('/api/control', async (req, res) => {
  try {
    const { delay } = req.body;
    await axios.post('http://service-a:3001/control/slow', { delay });
    res.json({ success: true, delay });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`✅ Dashboard running on http://localhost:${PORT}`);
});
EOF

mkdir -p dashboard/public
cat > dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cascading Timeouts Demo - System Design Interview Roadmap</title>
    <style>
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

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        header {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 16px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }

        h1 {
            color: #1e40af;
            font-size: 32px;
            margin-bottom: 10px;
        }

        .subtitle {
            color: #64748b;
            font-size: 16px;
        }

        .control-panel {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 16px;
            padding: 25px;
            margin-bottom: 30px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }

        .control-panel h2 {
            color: #1e40af;
            margin-bottom: 20px;
            font-size: 20px;
        }

        .controls {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            align-items: center;
        }

        button {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }

        .btn-start {
            background: #10b981;
            color: white;
        }

        .btn-start:hover {
            background: #059669;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(16, 185, 129, 0.4);
        }

        .btn-slow {
            background: #f59e0b;
            color: white;
        }

        .btn-slow:hover {
            background: #d97706;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(245, 158, 11, 0.4);
        }

        .btn-stop {
            background: #ef4444;
            color: white;
        }

        .btn-stop:hover {
            background: #dc2626;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(239, 68, 68, 0.4);
        }

        .btn-reset {
            background: #6366f1;
            color: white;
        }

        .btn-reset:hover {
            background: #4f46e5;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.4);
        }

        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 25px;
            margin-bottom: 30px;
        }

        .service-card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 16px;
            padding: 25px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            transition: transform 0.3s;
        }

        .service-card:hover {
            transform: translateY(-4px);
        }

        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }

        .service-name {
            font-size: 20px;
            font-weight: 700;
            color: #1e40af;
        }

        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
        }

        .status-healthy {
            background: #d1fae5;
            color: #065f46;
        }

        .status-warning {
            background: #fef3c7;
            color: #92400e;
        }

        .status-error {
            background: #fee2e2;
            color: #991b1b;
        }

        .metric {
            margin-bottom: 15px;
        }

        .metric-label {
            font-size: 13px;
            color: #64748b;
            margin-bottom: 5px;
        }

        .metric-value {
            font-size: 24px;
            font-weight: 700;
            color: #1e293b;
        }

        .metric-bar {
            height: 8px;
            background: #e2e8f0;
            border-radius: 4px;
            margin-top: 8px;
            overflow: hidden;
        }

        .metric-bar-fill {
            height: 100%;
            background: #10b981;
            transition: width 0.3s, background 0.3s;
        }

        .metric-bar-fill.warning {
            background: #f59e0b;
        }

        .metric-bar-fill.danger {
            background: #ef4444;
        }

        .cascade-indicator {
            background: linear-gradient(135deg, #fef3c7 0%, #fecaca 100%);
            border: 2px solid #f59e0b;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 30px;
            display: none;
        }

        .cascade-indicator.active {
            display: block;
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.8; }
        }

        .cascade-text {
            font-size: 18px;
            font-weight: 600;
            color: #92400e;
            text-align: center;
        }

        .info-box {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 16px;
            padding: 25px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }

        .info-box h3 {
            color: #1e40af;
            margin-bottom: 15px;
            font-size: 18px;
        }

        .info-box ul {
            list-style-position: inside;
            color: #475569;
            line-height: 1.8;
        }

        .live-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: #10b981;
            border-radius: 50%;
            margin-right: 8px;
            animation: blink 1.5s infinite;
        }

        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.3; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🚨 Cascading Timeouts Demo</h1>
            <p class="subtitle">Watch how a slow database query cascades through your entire system</p>
        </header>

        <div class="control-panel">
            <h2><span class="live-indicator"></span>Control Panel</h2>
            <div class="controls">
                <button class="btn-start" onclick="startLoad()">▶ Start Load Test (10 req/s)</button>
                <button class="btn-slow" onclick="makeSlow()">🐌 Make Service C Slow (10s)</button>
                <button class="btn-reset" onclick="resetNormal()">⚡ Reset to Normal</button>
                <button class="btn-stop" onclick="stopLoad()">⏹ Stop Load Test</button>
            </div>
        </div>

        <div class="cascade-indicator" id="cascadeIndicator">
            <div class="cascade-text">⚠️ CASCADE IN PROGRESS - Watch the timeouts propagate upward!</div>
        </div>

        <div class="services-grid">
            <div class="service-card">
                <div class="service-header">
                    <div class="service-name">Service A - API Gateway</div>
                    <span class="status-badge status-healthy" id="statusA">Healthy</span>
                </div>
                <div class="metric">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="requestsA">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Timeout Count</div>
                    <div class="metric-value" id="timeoutsA">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Active Requests (max: 100)</div>
                    <div class="metric-value" id="activeA">0</div>
                    <div class="metric-bar">
                        <div class="metric-bar-fill" id="activeBarA"></div>
                    </div>
                </div>
            </div>

            <div class="service-card">
                <div class="service-header">
                    <div class="service-name">Service B - Business Logic</div>
                    <span class="status-badge status-healthy" id="statusB">Healthy</span>
                </div>
                <div class="metric">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="requestsB">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Timeout Count</div>
                    <div class="metric-value" id="timeoutsB">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Active Requests (max: 50)</div>
                    <div class="metric-value" id="activeB">0</div>
                    <div class="metric-bar">
                        <div class="metric-bar-fill" id="activeBarB"></div>
                    </div>
                </div>
            </div>

            <div class="service-card">
                <div class="service-header">
                    <div class="service-name">Service C - Database</div>
                    <span class="status-badge status-healthy" id="statusC">Healthy</span>
                </div>
                <div class="metric">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="requestsC">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Artificial Delay</div>
                    <div class="metric-value" id="delayC">0ms</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Active Requests</div>
                    <div class="metric-value" id="activeC">0</div>
                </div>
            </div>
        </div>

        <div class="info-box">
            <h3>📖 How to Use This Demo</h3>
            <ul>
                <li><strong>Step 1:</strong> Click "Start Load Test" to send 10 requests per second through the system</li>
                <li><strong>Step 2:</strong> Watch the metrics - everything should be healthy with low active requests</li>
                <li><strong>Step 3:</strong> Click "Make Service C Slow" to inject a 10-second delay in the database</li>
                <li><strong>Step 4:</strong> Observe the cascade - Service B times out after 2s, Service A after 3s</li>
                <li><strong>Step 5:</strong> Notice how active requests pile up and timeout counts spike</li>
                <li><strong>Step 6:</strong> Click "Reset to Normal" to restore normal operation</li>
            </ul>
        </div>
    </div>

    <script>
        let loadInterval = null;

        async function updateMetrics() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();

                // Update Service A
                if (data.serviceA && !data.serviceA.error) {
                    document.getElementById('requestsA').textContent = data.serviceA.requestCount || 0;
                    document.getElementById('timeoutsA').textContent = data.serviceA.timeoutCount || 0;
                    document.getElementById('activeA').textContent = data.serviceA.activeRequests || 0;
                    
                    const activePercent = (data.serviceA.activeRequests / data.serviceA.maxConcurrent) * 100;
                    const barA = document.getElementById('activeBarA');
                    barA.style.width = activePercent + '%';
                    barA.className = 'metric-bar-fill';
                    if (activePercent > 70) barA.classList.add('danger');
                    else if (activePercent > 50) barA.classList.add('warning');

                    const statusA = document.getElementById('statusA');
                    if (data.serviceA.timeoutCount > 10) {
                        statusA.textContent = 'Degraded';
                        statusA.className = 'status-badge status-error';
                    } else if (data.serviceA.activeRequests > 50) {
                        statusA.textContent = 'Warning';
                        statusA.className = 'status-badge status-warning';
                    } else {
                        statusA.textContent = 'Healthy';
                        statusA.className = 'status-badge status-healthy';
                    }
                }

                // Update Service B
                if (data.serviceB && !data.serviceB.error) {
                    document.getElementById('requestsB').textContent = data.serviceB.requestCount || 0;
                    document.getElementById('timeoutsB').textContent = data.serviceB.timeoutCount || 0;
                    document.getElementById('activeB').textContent = data.serviceB.activeRequests || 0;
                    
                    const activePercent = (data.serviceB.activeRequests / data.serviceB.maxConcurrent) * 100;
                    const barB = document.getElementById('activeBarB');
                    barB.style.width = activePercent + '%';
                    barB.className = 'metric-bar-fill';
                    if (activePercent > 70) barB.classList.add('danger');
                    else if (activePercent > 50) barB.classList.add('warning');

                    const statusB = document.getElementById('statusB');
                    if (data.serviceB.timeoutCount > 10) {
                        statusB.textContent = 'Degraded';
                        statusB.className = 'status-badge status-error';
                    } else if (data.serviceB.activeRequests > 30) {
                        statusB.textContent = 'Warning';
                        statusB.className = 'status-badge status-warning';
                    } else {
                        statusB.textContent = 'Healthy';
                        statusB.className = 'status-badge status-healthy';
                    }
                }

                // Update Service C
                if (data.serviceC && !data.serviceC.error) {
                    document.getElementById('requestsC').textContent = data.serviceC.requestCount || 0;
                    document.getElementById('delayC').textContent = (data.serviceC.artificialDelay || 0) + 'ms';
                    document.getElementById('activeC').textContent = '—';

                    const statusC = document.getElementById('statusC');
                    if (data.serviceC.artificialDelay > 2000) {
                        statusC.textContent = 'Slow';
                        statusC.className = 'status-badge status-error';
                    } else {
                        statusC.textContent = 'Healthy';
                        statusC.className = 'status-badge status-healthy';
                    }
                }

                // Show cascade indicator if timeouts are happening
                const cascadeIndicator = document.getElementById('cascadeIndicator');
                if ((data.serviceA?.timeoutCount > 0 || data.serviceB?.timeoutCount > 0) && 
                    data.serviceC?.artificialDelay > 2000) {
                    cascadeIndicator.classList.add('active');
                } else {
                    cascadeIndicator.classList.remove('active');
                }

            } catch (error) {
                console.error('Error updating metrics:', error);
            }
        }

        async function makeSlow() {
            await fetch('/api/control', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ delay: 10000 })
            });
            alert('Service C is now responding in 10 seconds. Watch the cascade happen!');
        }

        async function resetNormal() {
            await fetch('/api/control', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ delay: 0 })
            });
            alert('Service C reset to normal (50-100ms). System recovering...');
        }

        function startLoad() {
            if (loadInterval) return;
            
            loadInterval = setInterval(async () => {
                // Send 10 requests per second
                for (let i = 0; i < 10; i++) {
                    fetch('http://localhost:3001/api/data').catch(() => {});
                }
            }, 1000);
            
            alert('Load test started: 10 requests/second');
        }

        function stopLoad() {
            if (loadInterval) {
                clearInterval(loadInterval);
                loadInterval = null;
                alert('Load test stopped');
            }
        }

        // Update metrics every 500ms
        setInterval(updateMetrics, 500);
        updateMetrics();
    </script>
</body>
</html>
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# Create Docker Compose file
echo "🔧 Creating Docker Compose configuration..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  service-c:
    build: ./service-c
    container_name: cascade-service-c
    ports:
      - "3003:3003"
    networks:
      - cascade-net

  service-b:
    build: ./service-b
    container_name: cascade-service-b
    ports:
      - "3002:3002"
    depends_on:
      - service-c
    networks:
      - cascade-net

  service-a:
    build: ./service-a
    container_name: cascade-service-a
    ports:
      - "3001:3001"
    depends_on:
      - service-b
    networks:
      - cascade-net

  dashboard:
    build: ./dashboard
    container_name: cascade-dashboard
    ports:
      - "3000:3000"
    depends_on:
      - service-a
      - service-b
      - service-c
    networks:
      - cascade-net

networks:
  cascade-net:
    driver: bridge
EOF

echo ""
echo "🏗️  Building Docker images..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      🎉 Demo is Ready!                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Dashboard:          http://localhost:3000"
echo "🌐 Service A (Gateway): http://localhost:3001"
echo "🔧 Service B (Logic):   http://localhost:3002"
echo "💾 Service C (Database): http://localhost:3003"
echo ""
echo "📖 Quick Start:"
echo "   1. Open http://localhost:3000 in your browser"
echo "   2. Click 'Start Load Test' to begin sending traffic"
echo "   3. Click 'Make Service C Slow' to trigger the cascade"
echo "   4. Watch the timeout counts increase and active requests pile up"
echo "   5. Click 'Reset to Normal' to restore the system"
echo ""
echo "🔍 To view logs:"
echo "   docker-compose logs -f"
echo ""
echo "🛑 To stop the demo:"
echo "   ./cleanup.sh"
echo ""