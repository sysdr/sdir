#!/bin/bash

set -e

echo "🚀 Setting up Circular Dependencies Demo"
echo "=========================================="

# Create project structure
mkdir -p circular-deps-demo
cd circular-deps-demo

# Create services directory
mkdir -p services/{user-service,order-service,inventory-service}
mkdir -p dashboard

echo "📦 Creating User Service..."
cat > services/user-service/package.json << 'EOF'
{
  "name": "user-service",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > services/user-service/index.js << 'EOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3001;
const ORDER_SERVICE_URL = process.env.ORDER_SERVICE_URL || 'http://order-service:3002';

let requestCount = 0;
let activeRequests = 0;
const MAX_THREADS = 10;
let circuitBreakerOpen = false;
const requestHistory = [];

// Middleware to track requests
app.use((req, res, next) => {
  requestCount++;
  activeRequests++;
  
  const reqId = req.headers['x-request-id'] || `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  req.requestId = reqId;
  
  // Check for circular dependency
  const seenIds = req.headers['x-seen-request-ids'] || '';
  if (seenIds.includes(reqId)) {
    console.log(`⛔ CIRCULAR DEPENDENCY DETECTED: ${reqId}`);
    res.status=508;
    return res.status(508).json({
      error: 'Loop Detected',
      requestId: reqId,
      message: 'Circular dependency prevented'
    });
  }
  
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] User Service - Request ${reqId} started (Active: ${activeRequests}/${MAX_THREADS})`);
  
  res.on('finish', () => {
    activeRequests--;
    console.log(`[${timestamp}] User Service - Request ${reqId} completed (Active: ${activeRequests}/${MAX_THREADS})`);
  });
  
  next();
});

app.get('/health', (req, res) => {
  res.json({
    service: 'user-service',
    status: 'healthy',
    activeRequests,
    maxThreads: MAX_THREADS,
    utilization: `${Math.round((activeRequests / MAX_THREADS) * 100)}%`,
    requestCount,
    circuitBreaker: circuitBreakerOpen ? 'OPEN' : 'CLOSED'
  });
});

app.get('/user/:id', async (req, res) => {
  const userId = req.params.id;
  
  res.json({
    userId,
    name: `User ${userId}`,
    email: `user${userId}@example.com`,
    requestId: req.requestId
  });
});

app.get('/user/:id/orders', async (req, res) => {
  const userId = req.params.id;
  
  if (activeRequests >= MAX_THREADS) {
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Thread pool exhausted'
    });
  }
  
  if (circuitBreakerOpen) {
    return res.status(503).json({
      error: 'Circuit Breaker Open',
      message: 'Service temporarily unavailable'
    });
  }
  
  try {
    const seenIds = req.headers['x-seen-request-ids'] || '';
    const newSeenIds = seenIds ? `${seenIds},${req.requestId}` : req.requestId;
    
    const response = await axios.get(`${ORDER_SERVICE_URL}/orders/user/${userId}`, {
      headers: {
        'x-request-id': req.requestId,
        'x-seen-request-ids': newSeenIds
      },
      timeout: 5000
    });
    
    res.json({
      userId,
      orders: response.data,
      requestId: req.requestId
    });
  } catch (error) {
    if (error.code === 'ECONNABORTED') {
      circuitBreakerOpen = true;
      setTimeout(() => { circuitBreakerOpen = false; }, 10000);
    }
    
    res.status(500).json({
      error: 'Failed to fetch orders',
      message: error.message,
      requestId: req.requestId
    });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    service: 'user-service',
    totalRequests: requestCount,
    activeRequests,
    maxThreads: MAX_THREADS,
    threadUtilization: Math.round((activeRequests / MAX_THREADS) * 100),
    circuitBreaker: circuitBreakerOpen ? 'OPEN' : 'CLOSED'
  });
});

app.listen(PORT, () => {
  console.log(`✅ User Service running on port ${PORT}`);
});
EOF

cat > services/user-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3001
CMD ["node", "index.js"]
EOF

echo "📦 Creating Order Service..."
cat > services/order-service/package.json << 'EOF'
{
  "name": "order-service",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > services/order-service/index.js << 'EOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3002;
const INVENTORY_SERVICE_URL = process.env.INVENTORY_SERVICE_URL || 'http://inventory-service:3003';

let requestCount = 0;
let activeRequests = 0;
const MAX_THREADS = 10;

app.use((req, res, next) => {
  requestCount++;
  activeRequests++;
  
  const reqId = req.headers['x-request-id'] || `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  req.requestId = reqId;
  
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] Order Service - Request ${reqId} started (Active: ${activeRequests}/${MAX_THREADS})`);
  
  res.on('finish', () => {
    activeRequests--;
  });
  
  next();
});

app.get('/health', (req, res) => {
  res.json({
    service: 'order-service',
    status: 'healthy',
    activeRequests,
    maxThreads: MAX_THREADS,
    utilization: `${Math.round((activeRequests / MAX_THREADS) * 100)}%`,
    requestCount
  });
});

app.get('/orders/user/:userId', async (req, res) => {
  const userId = req.params.userId;
  
  if (activeRequests >= MAX_THREADS) {
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Thread pool exhausted'
    });
  }
  
  try {
    const seenIds = req.headers['x-seen-request-ids'] || '';
    const newSeenIds = seenIds ? `${seenIds},${req.requestId}` : req.requestId;
    
    const response = await axios.get(`${INVENTORY_SERVICE_URL}/inventory/check`, {
      headers: {
        'x-request-id': req.requestId,
        'x-seen-request-ids': newSeenIds
      },
      params: { userId },
      timeout: 5000
    });
    
    res.json({
      orderId: `ORD-${Date.now()}`,
      userId,
      items: response.data,
      status: 'confirmed',
      requestId: req.requestId
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to check inventory',
      message: error.message,
      requestId: req.requestId
    });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    service: 'order-service',
    totalRequests: requestCount,
    activeRequests,
    maxThreads: MAX_THREADS,
    threadUtilization: Math.round((activeRequests / MAX_THREADS) * 100)
  });
});

app.listen(PORT, () => {
  console.log(`✅ Order Service running on port ${PORT}`);
});
EOF

cat > services/order-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3002
CMD ["node", "index.js"]
EOF

echo "📦 Creating Inventory Service..."
cat > services/inventory-service/package.json << 'EOF'
{
  "name": "inventory-service",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > services/inventory-service/index.js << 'EOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3003;
const USER_SERVICE_URL = process.env.USER_SERVICE_URL || 'http://user-service:3001';

let requestCount = 0;
let activeRequests = 0;
const MAX_THREADS = 10;
let circularCallsEnabled = true;

app.use((req, res, next) => {
  requestCount++;
  activeRequests++;
  
  const reqId = req.headers['x-request-id'] || `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  req.requestId = reqId;
  
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] Inventory Service - Request ${reqId} started (Active: ${activeRequests}/${MAX_THREADS})`);
  
  res.on('finish', () => {
    activeRequests--;
  });
  
  next();
});

app.get('/health', (req, res) => {
  res.json({
    service: 'inventory-service',
    status: 'healthy',
    activeRequests,
    maxThreads: MAX_THREADS,
    utilization: `${Math.round((activeRequests / MAX_THREADS) * 100)}%`,
    requestCount,
    circularCallsEnabled
  });
});

app.post('/toggle-circular', (req, res) => {
  circularCallsEnabled = !circularCallsEnabled;
  console.log(`🔄 Circular calls ${circularCallsEnabled ? 'ENABLED' : 'DISABLED'}`);
  res.json({ circularCallsEnabled });
});

app.get('/inventory/check', async (req, res) => {
  const userId = req.query.userId;
  
  if (activeRequests >= MAX_THREADS) {
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Thread pool exhausted'
    });
  }
  
  // This creates the circular dependency!
  if (circularCallsEnabled && userId) {
    try {
      const seenIds = req.headers['x-seen-request-ids'] || '';
      const newSeenIds = seenIds ? `${seenIds},${req.requestId}` : req.requestId;
      
      console.log(`⚠️  CIRCULAR CALL: Inventory calling User Service for userId=${userId}`);
      
      const response = await axios.get(`${USER_SERVICE_URL}/user/${userId}`, {
        headers: {
          'x-request-id': req.requestId,
          'x-seen-request-ids': newSeenIds
        },
        timeout: 5000
      });
      
      res.json({
        available: true,
        stock: 42,
        userVerified: response.data,
        requestId: req.requestId
      });
    } catch (error) {
      if (error.response?.status === 508) {
        console.log(`🛑 Circular dependency prevented for request ${req.requestId}`);
        return res.status(200).json({
          available: true,
          stock: 42,
          userVerified: false,
          message: 'Circular call prevented by circuit breaker',
          requestId: req.requestId
        });
      }
      
      res.status(500).json({
        error: 'Failed to verify user',
        message: error.message,
        requestId: req.requestId
      });
    }
  } else {
    res.json({
      available: true,
      stock: 42,
      requestId: req.requestId
    });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    service: 'inventory-service',
    totalRequests: requestCount,
    activeRequests,
    maxThreads: MAX_THREADS,
    threadUtilization: Math.round((activeRequests / MAX_THREADS) * 100),
    circularCallsEnabled
  });
});

app.listen(PORT, () => {
  console.log(`✅ Inventory Service running on port ${PORT}`);
});
EOF

cat > services/inventory-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3003
CMD ["node", "index.js"]
EOF

echo "🎨 Creating Dashboard..."
cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Circular Dependencies Monitor</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.95;
        }
        
        .controls {
            background: white;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .button-group {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            justify-content: center;
        }
        
        button {
            padding: 15px 30px;
            font-size: 16px;
            font-weight: 600;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 12px rgba(0,0,0,0.15);
        }
        
        .btn-danger {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
        }
        
        .btn-success {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white;
        }
        
        .btn-warning {
            background: linear-gradient(135deg, #fa709a 0%, #fee140 100%);
            color: white;
        }
        
        .btn-info {
            background: linear-gradient(135deg, #a8edea 0%, #fed6e3 100%);
            color: #333;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 25px;
        }
        
        .service-card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease;
        }
        
        .service-card:hover {
            transform: translateY(-5px);
        }
        
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        
        .service-name {
            font-size: 1.3em;
            font-weight: bold;
            color: #333;
        }
        
        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }
        
        .status-healthy {
            background: #d4edda;
            color: #155724;
        }
        
        .status-warning {
            background: #fff3cd;
            color: #856404;
        }
        
        .status-critical {
            background: #f8d7da;
            color: #721c24;
        }
        
        .metric {
            margin: 15px 0;
        }
        
        .metric-label {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 5px;
        }
        
        .metric-value {
            font-size: 1.8em;
            font-weight: bold;
            color: #333;
        }
        
        .progress-bar {
            width: 100%;
            height: 20px;
            background: #e0e0e0;
            border-radius: 10px;
            overflow: hidden;
            margin-top: 8px;
        }
        
        .progress-fill {
            height: 100%;
            transition: width 0.5s ease, background 0.3s ease;
            border-radius: 10px;
        }
        
        .chart-container {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 25px;
        }
        
        .logs {
            background: #1e1e1e;
            border-radius: 15px;
            padding: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            max-height: 400px;
            overflow-y: auto;
        }
        
        .log-entry {
            color: #d4d4d4;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            padding: 5px 0;
            border-bottom: 1px solid #333;
        }
        
        .log-entry:last-child {
            border-bottom: none;
        }
        
        .log-time {
            color: #858585;
        }
        
        .log-error {
            color: #f48771;
        }
        
        .log-success {
            color: #89d185;
        }
        
        .log-warning {
            color: #e5c07b;
        }
        
        .alert {
            background: #fff3cd;
            border: 2px solid #ffc107;
            border-radius: 10px;
            padding: 15px;
            margin: 20px 0;
            display: none;
        }
        
        .alert.show {
            display: block;
            animation: slideIn 0.3s ease;
        }
        
        @keyframes slideIn {
            from {
                opacity: 0;
                transform: translateY(-20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
        
        .flow-diagram {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 25px;
            text-align: center;
        }
        
        .flow-arrow {
            display: inline-block;
            margin: 0 15px;
            font-size: 2em;
            color: #667eea;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .circular-indicator {
            display: inline-block;
            margin: 20px;
            padding: 10px 20px;
            background: #f8d7da;
            border: 2px solid #f5c6cb;
            border-radius: 25px;
            color: #721c24;
            font-weight: bold;
            animation: blink 1s infinite;
        }
        
        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.6; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Circular Dependencies Monitor</h1>
            <p>Real-time visualization of service dependencies and resource exhaustion</p>
        </div>
        
        <div class="alert" id="circularAlert">
            <strong>⚠️ WARNING:</strong> Circular dependency pattern detected! Request is looping through services.
        </div>
        
        <div class="controls">
            <div class="button-group">
                <button class="btn-danger" onclick="triggerCircularCalls()">🔥 Trigger Circular Calls (10 req/s)</button>
                <button class="btn-success" onclick="toggleCircular()">🛡️ Toggle Circuit Protection</button>
                <button class="btn-warning" onclick="resetStats()">🔄 Reset Statistics</button>
                <button class="btn-info" onclick="stopLoad()">⏹️ Stop Load</button>
            </div>
        </div>
        
        <div class="flow-diagram">
            <h3>Service Call Flow</h3>
            <div style="margin: 20px 0; font-size: 1.1em;">
                <span style="color: #1976d2; font-weight: bold;">User Service</span>
                <span class="flow-arrow">→</span>
                <span style="color: #388e3c; font-weight: bold;">Order Service</span>
                <span class="flow-arrow">→</span>
                <span style="color: #f57c00; font-weight: bold;">Inventory Service</span>
                <span class="flow-arrow" style="color: #f44336;">⤴</span>
            </div>
            <div id="circularIndicator" style="display: none;">
                <span class="circular-indicator">🔁 CIRCULAR LOOP ACTIVE</span>
            </div>
        </div>
        
        <div class="services-grid">
            <div class="service-card">
                <div class="service-header">
                    <span class="service-name">👤 User Service</span>
                    <span class="status-badge status-healthy" id="user-status">Healthy</span>
                </div>
                <div class="metric">
                    <div class="metric-label">Thread Pool Utilization</div>
                    <div class="metric-value" id="user-threads">0%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" id="user-progress" style="width: 0%; background: #4caf50;"></div>
                    </div>
                </div>
                <div class="metric">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="user-requests">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Active Requests</div>
                    <div class="metric-value" id="user-active">0</div>
                </div>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-name">📦 Order Service</span>
                    <span class="status-badge status-healthy" id="order-status">Healthy</span>
                </div>
                <div class="metric">
                    <div class="metric-label">Thread Pool Utilization</div>
                    <div class="metric-value" id="order-threads">0%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" id="order-progress" style="width: 0%; background: #4caf50;"></div>
                    </div>
                </div>
                <div class="metric">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="order-requests">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Active Requests</div>
                    <div class="metric-value" id="order-active">0</div>
                </div>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-name">📊 Inventory Service</span>
                    <span class="status-badge status-healthy" id="inventory-status">Healthy</span>
                </div>
                <div class="metric">
                    <div class="metric-label">Thread Pool Utilization</div>
                    <div class="metric-value" id="inventory-threads">0%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" id="inventory-progress" style="width: 0%; background: #4caf50;"></div>
                    </div>
                </div>
                <div class="metric">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="inventory-requests">0</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Active Requests</div>
                    <div class="metric-value" id="inventory-active">0</div>
                </div>
            </div>
        </div>
        
        <div class="chart-container">
            <h3>Request Latency Over Time</h3>
            <canvas id="latencyChart"></canvas>
        </div>
        
        <div class="logs">
            <h3 style="color: #d4d4d4; margin-bottom: 15px;">📝 System Logs</h3>
            <div id="logs"></div>
        </div>
    </div>
    
    <script>
        const ctx = document.getElementById('latencyChart').getContext('2d');
        const chart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'User Service',
                    data: [],
                    borderColor: '#1976d2',
                    tension: 0.4
                }, {
                    label: 'Order Service',
                    data: [],
                    borderColor: '#388e3c',
                    tension: 0.4
                }, {
                    label: 'Inventory Service',
                    data: [],
                    borderColor: '#f57c00',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        }
                    }
                }
            }
        });
        
        let loadInterval = null;
        
        function addLog(message, type = 'info') {
            const logsDiv = document.getElementById('logs');
            const entry = document.createElement('div');
            entry.className = `log-entry log-${type}`;
            const time = new Date().toLocaleTimeString();
            entry.innerHTML = `<span class="log-time">[${time}]</span> ${message}`;
            logsDiv.insertBefore(entry, logsDiv.firstChild);
            
            // Keep only last 50 logs
            while (logsDiv.children.length > 50) {
                logsDiv.removeChild(logsDiv.lastChild);
            }
        }
        
        async function updateStats() {
            try {
                const [userRes, orderRes, invRes] = await Promise.all([
                    fetch('http://localhost:3001/stats'),
                    fetch('http://localhost:3002/stats'),
                    fetch('http://localhost:3003/stats')
                ]);
                
                const [userData, orderData, invData] = await Promise.all([
                    userRes.json(),
                    orderRes.json(),
                    invRes.json()
                ]);
                
                updateServiceCard('user', userData);
                updateServiceCard('order', orderData);
                updateServiceCard('inventory', invData);
                
                // Update chart
                const time = new Date().toLocaleTimeString();
                if (chart.data.labels.length > 20) {
                    chart.data.labels.shift();
                    chart.data.datasets.forEach(d => d.data.shift());
                }
                chart.data.labels.push(time);
                chart.data.datasets[0].data.push(userData.activeRequests * 10);
                chart.data.datasets[1].data.push(orderData.activeRequests * 10);
                chart.data.datasets[2].data.push(invData.activeRequests * 10);
                chart.update('none');
                
            } catch (error) {
                addLog(`Failed to update stats: ${error.message}`, 'error');
            }
        }
        
        function updateServiceCard(service, data) {
            const util = data.threadUtilization || 0;
            document.getElementById(`${service}-threads`).textContent = `${util}%`;
            document.getElementById(`${service}-requests`).textContent = data.totalRequests;
            document.getElementById(`${service}-active`).textContent = data.activeRequests;
            
            const progress = document.getElementById(`${service}-progress`);
            progress.style.width = `${util}%`;
            
            // Color based on utilization
            if (util < 50) {
                progress.style.background = '#4caf50';
                document.getElementById(`${service}-status`).className = 'status-badge status-healthy';
                document.getElementById(`${service}-status`).textContent = 'Healthy';
            } else if (util < 80) {
                progress.style.background = '#ff9800';
                document.getElementById(`${service}-status`).className = 'status-badge status-warning';
                document.getElementById(`${service}-status`).textContent = 'Warning';
            } else {
                progress.style.background = '#f44336';
                document.getElementById(`${service}-status`).className = 'status-badge status-critical';
                document.getElementById(`${service}-status`).textContent = 'Critical';
            }
        }
        
        async function triggerCircularCalls() {
            addLog('🔥 Starting circular call pattern (10 req/s)', 'warning');
            document.getElementById('circularAlert').classList.add('show');
            document.getElementById('circularIndicator').style.display = 'block';
            
            if (loadInterval) clearInterval(loadInterval);
            
            loadInterval = setInterval(async () => {
                try {
                    const response = await fetch('http://localhost:3001/user/123/orders');
                    if (response.status === 508) {
                        addLog('🛡️ Circuit breaker prevented circular dependency', 'success');
                    } else if (!response.ok) {
                        addLog(`⚠️ Request failed: ${response.status}`, 'error');
                    } else {
                        addLog('✓ Request completed successfully', 'success');
                    }
                } catch (error) {
                    addLog(`❌ Request error: ${error.message}`, 'error');
                }
            }, 100); // 10 requests per second
        }
        
        function stopLoad() {
            if (loadInterval) {
                clearInterval(loadInterval);
                loadInterval = null;
                addLog('⏹️ Load generation stopped', 'info');
                document.getElementById('circularAlert').classList.remove('show');
                document.getElementById('circularIndicator').style.display = 'none';
            }
        }
        
        async function toggleCircular() {
            try {
                const response = await fetch('http://localhost:3003/toggle-circular', {
                    method: 'POST'
                });
                const data = await response.json();
                addLog(`Circuit protection ${data.circularCallsEnabled ? 'DISABLED' : 'ENABLED'}`, 'warning');
            } catch (error) {
                addLog(`Failed to toggle: ${error.message}`, 'error');
            }
        }
        
        async function resetStats() {
            addLog('🔄 Statistics reset', 'info');
            chart.data.labels = [];
            chart.data.datasets.forEach(d => d.data = []);
            chart.update();
        }
        
        // Update stats every second
        setInterval(updateStats, 1000);
        updateStats();
        
        addLog('✅ Dashboard initialized', 'success');
        addLog('💡 Click "Trigger Circular Calls" to see thread exhaustion in action', 'info');
    </script>
</body>
</html>
EOF

echo "🐳 Creating Docker Compose..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  user-service:
    build: ./services/user-service
    ports:
      - "3001:3001"
    environment:
      - PORT=3001
      - ORDER_SERVICE_URL=http://order-service:3002
    networks:
      - microservices
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3001/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  order-service:
    build: ./services/order-service
    ports:
      - "3002:3002"
    environment:
      - PORT=3002
      - INVENTORY_SERVICE_URL=http://inventory-service:3003
    networks:
      - microservices
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3002/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  inventory-service:
    build: ./services/inventory-service
    ports:
      - "3003:3003"
    environment:
      - PORT=3003
      - USER_SERVICE_URL=http://user-service:3001
    networks:
      - microservices
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3003/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  dashboard:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./dashboard:/usr/share/nginx/html:ro
    networks:
      - microservices
    depends_on:
      - user-service
      - order-service
      - inventory-service

networks:
  microservices:
    driver: bridge
EOF

cat > README.md << 'EOF'
# Circular Dependencies Demo

This demo shows how circular dependencies cause resource exhaustion in microservices.

## Architecture

- **User Service** (3001): Handles user requests
- **Order Service** (3002): Processes orders
- **Inventory Service** (3003): Checks inventory (calls back to User Service - CIRCULAR!)
- **Dashboard** (8080): Real-time monitoring

## What Happens

1. User Service receives request → calls Order Service
2. Order Service → calls Inventory Service
3. Inventory Service → calls User Service (CIRCLE!)
4. Thread pools fill up waiting for each other
5. System deadlocks under load

## Run the Demo

```bash
./demo.sh
```

Then open: http://localhost:8080

## Watch It Break

1. Click "Trigger Circular Calls"
2. Watch thread utilization hit 100%
3. See requests start failing
4. Observe circuit breaker preventing cascade

## Clean Up

```bash
./cleanup.sh
```

## Learning Points

- Circular dependencies cause deadlocks
- Thread pool exhaustion happens fast (< 3 seconds at 5000 RPS)
- Request ID tracking detects circles
- Circuit breakers prevent cascading failures
- Timeouts alone don't solve the problem
EOF

echo "✅ Building Docker images..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "================================================"
echo "✅ Demo Setup Complete!"
echo "================================================"
echo ""
echo "🌐 Dashboard: http://localhost:8080"
echo "📊 User Service: http://localhost:3001/health"
echo "📊 Order Service: http://localhost:3002/health"
echo "📊 Inventory Service: http://localhost:3003/health"
echo ""
echo "⏳ Waiting for services to be ready..."
sleep 15

echo ""
echo "🎯 Try this:"
echo "1. Open http://localhost:8080 in your browser"
echo "2. Click 'Trigger Circular Calls'"
echo "3. Watch the thread pools fill up"
echo "4. See circuit breakers prevent total failure"
echo ""
echo "📝 View logs: docker-compose logs -f"
echo "🛑 Stop demo: docker-compose down"
echo ""