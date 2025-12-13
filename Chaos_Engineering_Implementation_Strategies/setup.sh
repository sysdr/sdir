#!/bin/bash

# Chaos Engineering Implementation Demo Setup
# Creates a microservices system with integrated chaos engineering tools

set -e

echo "🔧 Setting up Chaos Engineering Demo..."

# Create directory structure
mkdir -p chaos-demo/{frontend,payment-service,inventory-service,chaos-controller,dashboard}

# 1. PAYMENT SERVICE (Node.js + Express)
cat > chaos-demo/payment-service/server.js << 'EOF'
const express = require('express');
const app = express();
app.use(express.json());

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

let chaosConfig = {
  errorRate: 0,
  latency: 0,
  enabled: false
};

let metrics = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  avgLatency: 0
};

// Chaos injection middleware
function injectChaos(req, res, next) {
  // Skip chaos injection for control and monitoring endpoints
  if (req.path.startsWith('/chaos/') || req.path === '/health' || req.path === '/metrics') {
    return next();
  }
  
  metrics.totalRequests++;
  
  if (chaosConfig.enabled && Math.random() < chaosConfig.errorRate) {
    metrics.failedRequests++;
    return res.status(500).json({ error: 'Chaos injected error', service: 'payment' });
  }
  
  const delay = chaosConfig.enabled ? chaosConfig.latency : 0;
  setTimeout(() => next(), delay);
}

app.use(injectChaos);

// Payment processing endpoint
app.post('/api/process', (req, res) => {
  const { amount, orderId } = req.body;
  
  const startTime = Date.now();
  const processingTime = Math.random() * 100 + 50;
  
  setTimeout(() => {
    const transactionId = `TXN-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    metrics.successfulRequests++;
    const latency = Date.now() - startTime;
    metrics.avgLatency = ((metrics.avgLatency * (metrics.successfulRequests - 1)) + latency) / metrics.successfulRequests;
    
    res.json({
      success: true,
      transactionId,
      amount,
      orderId,
      processingTime: latency
    });
  }, processingTime);
});

// Chaos control endpoint
app.post('/chaos/config', (req, res) => {
  chaosConfig = { ...chaosConfig, ...req.body };
  console.log('Chaos config updated:', chaosConfig);
  res.json({ success: true, config: chaosConfig });
});

app.get('/chaos/config', (req, res) => {
  res.json(chaosConfig);
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.json({
    ...metrics,
    successRate: metrics.totalRequests > 0 ? (metrics.successfulRequests / metrics.totalRequests * 100).toFixed(2) : 100,
    chaosConfig
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment' });
});

const PORT = 3001;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`💳 Payment Service running on port ${PORT}`);
});
EOF

cat > chaos-demo/payment-service/package.json << 'EOF'
{
  "name": "payment-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# 2. INVENTORY SERVICE (Node.js + Express)
cat > chaos-demo/inventory-service/server.js << 'EOF'
const express = require('express');
const app = express();
app.use(express.json());

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

let chaosConfig = {
  errorRate: 0,
  latency: 0,
  enabled: false
};

let metrics = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  avgLatency: 0
};

const inventory = {
  'ITEM-001': { name: 'Laptop', stock: 50, price: 999.99 },
  'ITEM-002': { name: 'Mouse', stock: 200, price: 29.99 },
  'ITEM-003': { name: 'Keyboard', stock: 150, price: 79.99 },
  'ITEM-004': { name: 'Monitor', stock: 75, price: 299.99 },
  'ITEM-005': { name: 'Headphones', stock: 120, price: 149.99 }
};

// Chaos injection middleware
function injectChaos(req, res, next) {
  // Skip chaos injection for control and monitoring endpoints
  if (req.path.startsWith('/chaos/') || req.path === '/health' || req.path === '/metrics') {
    return next();
  }
  
  metrics.totalRequests++;
  
  if (chaosConfig.enabled && Math.random() < chaosConfig.errorRate) {
    metrics.failedRequests++;
    return res.status(503).json({ error: 'Chaos injected error', service: 'inventory' });
  }
  
  const delay = chaosConfig.enabled ? chaosConfig.latency : 0;
  setTimeout(() => next(), delay);
}

app.use(injectChaos);

// Check stock endpoint
app.post('/api/check', (req, res) => {
  const { itemId, quantity } = req.body;
  const startTime = Date.now();
  
  setTimeout(() => {
    const item = inventory[itemId];
    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    metrics.successfulRequests++;
    const latency = Date.now() - startTime;
    metrics.avgLatency = ((metrics.avgLatency * (metrics.successfulRequests - 1)) + latency) / metrics.successfulRequests;
    
    res.json({
      available: item.stock >= quantity,
      item: item.name,
      currentStock: item.stock,
      requestedQuantity: quantity,
      price: item.price
    });
  }, Math.random() * 80 + 20);
});

// Reserve stock endpoint
app.post('/api/reserve', (req, res) => {
  const { itemId, quantity } = req.body;
  const item = inventory[itemId];
  
  if (item && item.stock >= quantity) {
    item.stock -= quantity;
    metrics.successfulRequests++;
    res.json({ success: true, remainingStock: item.stock });
  } else {
    metrics.failedRequests++;
    res.status(400).json({ error: 'Insufficient stock' });
  }
});

// Chaos control endpoint
app.post('/chaos/config', (req, res) => {
  chaosConfig = { ...chaosConfig, ...req.body };
  console.log('Chaos config updated:', chaosConfig);
  res.json({ success: true, config: chaosConfig });
});

app.get('/chaos/config', (req, res) => {
  res.json(chaosConfig);
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.json({
    ...metrics,
    successRate: metrics.totalRequests > 0 ? (metrics.successfulRequests / metrics.totalRequests * 100).toFixed(2) : 100,
    chaosConfig,
    inventoryStatus: inventory
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'inventory' });
});

const PORT = 3002;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`📦 Inventory Service running on port ${PORT}`);
});
EOF

cat > chaos-demo/inventory-service/package.json << 'EOF'
{
  "name": "inventory-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# 3. FRONTEND SERVICE WITH RESILIENCE PATTERNS (Node.js + Express + Circuit Breaker)
cat > chaos-demo/frontend/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const app = express();
app.use(express.json());
app.use(express.static('public'));

// Circuit Breaker implementation
class CircuitBreaker {
  constructor(service, threshold = 5, timeout = 10000) {
    this.service = service;
    this.failureThreshold = threshold;
    this.timeout = timeout;
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
  }

  async call(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
        console.log(`Circuit breaker HALF_OPEN for ${this.service}`);
      } else {
        throw new Error(`Circuit breaker OPEN for ${this.service}`);
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  onSuccess() {
    this.failureCount = 0;
    if (this.state === 'HALF_OPEN') {
      this.state = 'CLOSED';
      console.log(`Circuit breaker CLOSED for ${this.service}`);
    }
  }

  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.failureThreshold) {
      this.state = 'OPEN';
      console.log(`Circuit breaker OPEN for ${this.service} (failures: ${this.failureCount})`);
    }
  }

  getState() {
    return {
      service: this.service,
      state: this.state,
      failureCount: this.failureCount,
      lastFailureTime: this.lastFailureTime
    };
  }
}

const paymentBreaker = new CircuitBreaker('payment', 3, 5000);
const inventoryBreaker = new CircuitBreaker('inventory', 3, 5000);

let orderMetrics = {
  totalOrders: 0,
  successfulOrders: 0,
  failedOrders: 0,
  degradedOrders: 0
};

// Retry with exponential backoff
async function retryWithBackoff(fn, maxRetries = 3, baseDelay = 100) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      const delay = baseDelay * Math.pow(2, i);
      console.log(`Retry ${i + 1}/${maxRetries} after ${delay}ms`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

// Order processing with resilience patterns
app.post('/api/order', async (req, res) => {
  const { itemId, quantity, paymentAmount } = req.body;
  orderMetrics.totalOrders++;
  
  const orderId = `ORD-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  let inventoryChecked = false;
  let paymentProcessed = false;
  let degraded = false;

  try {
    // Check inventory with circuit breaker and retry
    try {
      await inventoryBreaker.call(async () => {
        await retryWithBackoff(async () => {
          const response = await axios.post('http://inventory-service:3002/api/check', 
            { itemId, quantity },
            { timeout: 5000 }
          );
          inventoryChecked = response.data.available;
          if (!inventoryChecked) {
            throw new Error('Insufficient stock');
          }
        });
      });
    } catch (error) {
      console.log('Inventory check failed, degrading gracefully');
      degraded = true;
      // Graceful degradation: proceed with order, mark for manual verification
    }

    // Process payment with circuit breaker and retry
    try {
      await paymentBreaker.call(async () => {
        await retryWithBackoff(async () => {
          await axios.post('http://payment-service:3001/api/process',
            { amount: paymentAmount, orderId },
            { timeout: 5000 }
          );
          paymentProcessed = true;
        });
      });
    } catch (error) {
      orderMetrics.failedOrders++;
      return res.status(500).json({
        success: false,
        orderId,
        error: 'Payment processing failed',
        circuitBreakers: {
          payment: paymentBreaker.getState(),
          inventory: inventoryBreaker.getState()
        }
      });
    }

    if (degraded) {
      orderMetrics.degradedOrders++;
    } else {
      orderMetrics.successfulOrders++;
    }

    res.json({
      success: true,
      orderId,
      inventoryChecked,
      paymentProcessed,
      degraded,
      message: degraded ? 'Order accepted with manual verification required' : 'Order processed successfully',
      circuitBreakers: {
        payment: paymentBreaker.getState(),
        inventory: inventoryBreaker.getState()
      }
    });

  } catch (error) {
    orderMetrics.failedOrders++;
    res.status(500).json({
      success: false,
      orderId,
      error: error.message,
      circuitBreakers: {
        payment: paymentBreaker.getState(),
        inventory: inventoryBreaker.getState()
      }
    });
  }
});

// Get system metrics
app.get('/api/metrics', async (req, res) => {
  try {
    const [paymentMetrics, inventoryMetrics] = await Promise.allSettled([
      axios.get('http://payment-service:3001/metrics', { timeout: 2000 }),
      axios.get('http://inventory-service:3002/metrics', { timeout: 2000 })
    ]);

    res.json({
      frontend: {
        ...orderMetrics,
        successRate: orderMetrics.totalOrders > 0 
          ? ((orderMetrics.successfulOrders / orderMetrics.totalOrders) * 100).toFixed(2) 
          : 100,
        circuitBreakers: {
          payment: paymentBreaker.getState(),
          inventory: inventoryBreaker.getState()
        }
      },
      payment: paymentMetrics.status === 'fulfilled' ? paymentMetrics.value.data : { error: 'unavailable' },
      inventory: inventoryMetrics.status === 'fulfilled' ? inventoryMetrics.value.data : { error: 'unavailable' }
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch metrics' });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'frontend' });
});

const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🌐 Frontend Service running on port ${PORT}`);
});
EOF

cat > chaos-demo/frontend/package.json << 'EOF'
{
  "name": "frontend-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0"
  }
}
EOF

# 4. DASHBOARD (HTML + JavaScript with real-time updates)
mkdir -p chaos-demo/frontend/public
cat > chaos-demo/frontend/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Chaos Engineering Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        h1 {
            color: white;
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }

        .card {
            background: white;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }

        .card h2 {
            color: #4a5568;
            font-size: 1.3em;
            margin-bottom: 16px;
            border-bottom: 3px solid #667eea;
            padding-bottom: 8px;
        }

        .metric {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #e2e8f0;
        }

        .metric:last-child {
            border-bottom: none;
        }

        .metric-label {
            color: #718096;
            font-weight: 500;
        }

        .metric-value {
            color: #2d3748;
            font-weight: 700;
            font-size: 1.1em;
        }

        .status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: 600;
        }

        .status-healthy {
            background: #c6f6d5;
            color: #22543d;
        }

        .status-degraded {
            background: #feebc8;
            color: #7c2d12;
        }

        .status-failed {
            background: #fed7d7;
            color: #742a2a;
        }

        .circuit-breaker {
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 12px;
            background: #f7fafc;
        }

        .circuit-state {
            display: inline-block;
            padding: 6px 12px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9em;
        }

        .state-closed {
            background: #c6f6d5;
            color: #22543d;
        }

        .state-open {
            background: #fed7d7;
            color: #742a2a;
        }

        .state-half-open {
            background: #feebc8;
            color: #7c2d12;
        }

        .chaos-controls {
            background: white;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 20px;
        }

        .control-group {
            margin-bottom: 20px;
        }

        .control-group label {
            display: block;
            color: #4a5568;
            font-weight: 600;
            margin-bottom: 8px;
        }

        .control-row {
            display: flex;
            gap: 12px;
            align-items: center;
            margin-bottom: 12px;
        }

        input[type="range"] {
            flex: 1;
            height: 6px;
            border-radius: 3px;
            background: #e2e8f0;
            outline: none;
        }

        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            width: 18px;
            height: 18px;
            border-radius: 50%;
            background: #667eea;
            cursor: pointer;
        }

        button {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            font-size: 0.95em;
        }

        .btn-primary {
            background: #667eea;
            color: white;
        }

        .btn-primary:hover {
            background: #5a67d8;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }

        .btn-danger {
            background: #f56565;
            color: white;
        }

        .btn-danger:hover {
            background: #e53e3e;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(245, 101, 101, 0.4);
        }

        .btn-success {
            background: #48bb78;
            color: white;
        }

        .btn-success:hover {
            background: #38a169;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(72, 187, 120, 0.4);
        }

        .value-display {
            min-width: 60px;
            text-align: center;
            font-weight: 600;
            color: #667eea;
        }

        .log-container {
            background: #2d3748;
            border-radius: 8px;
            padding: 16px;
            max-height: 200px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 0.85em;
        }

        .log-entry {
            color: #a0aec0;
            margin-bottom: 6px;
        }

        .log-error {
            color: #fc8181;
        }

        .log-success {
            color: #68d391;
        }

        .log-warning {
            color: #f6ad55;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧪 Chaos Engineering Dashboard</h1>
        
        <div class="chaos-controls">
            <h2 style="color: #4a5568; margin-bottom: 20px;">Chaos Injection Controls</h2>
            
            <div class="control-group">
                <label>Payment Service - Error Rate: <span id="paymentErrorDisplay">0%</span></label>
                <div class="control-row">
                    <input type="range" id="paymentError" min="0" max="100" value="0" step="5">
                    <button class="btn-danger" onclick="injectChaos('payment')">Inject Chaos</button>
                </div>
            </div>

            <div class="control-group">
                <label>Payment Service - Latency: <span id="paymentLatencyDisplay">0ms</span></label>
                <div class="control-row">
                    <input type="range" id="paymentLatency" min="0" max="5000" value="0" step="100">
                </div>
            </div>

            <div class="control-group">
                <label>Inventory Service - Error Rate: <span id="inventoryErrorDisplay">0%</span></label>
                <div class="control-row">
                    <input type="range" id="inventoryError" min="0" max="100" value="0" step="5">
                    <button class="btn-danger" onclick="injectChaos('inventory')">Inject Chaos</button>
                </div>
            </div>

            <div class="control-group">
                <label>Inventory Service - Latency: <span id="inventoryLatencyDisplay">0ms</span></label>
                <div class="control-row">
                    <input type="range" id="inventoryLatency" min="0" max="5000" value="0" step="100">
                </div>
            </div>

            <div style="display: flex; gap: 12px; margin-top: 24px;">
                <button class="btn-success" onclick="generateLoad()">Generate Load (10 Orders)</button>
                <button class="btn-primary" onclick="resetChaos()">Reset All</button>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>Circuit Breakers</h2>
                <div id="circuitBreakers"></div>
            </div>

            <div class="card">
                <h2>Frontend Metrics</h2>
                <div id="frontendMetrics"></div>
            </div>

            <div class="card">
                <h2>Payment Service</h2>
                <div id="paymentMetrics"></div>
            </div>

            <div class="card">
                <h2>Inventory Service</h2>
                <div id="inventoryMetrics"></div>
            </div>
        </div>

        <div class="card">
            <h2>Activity Log</h2>
            <div class="log-container" id="activityLog"></div>
        </div>
    </div>

    <script>
        // Update slider displays
        document.getElementById('paymentError').oninput = function() {
            document.getElementById('paymentErrorDisplay').textContent = this.value + '%';
        };
        document.getElementById('paymentLatency').oninput = function() {
            document.getElementById('paymentLatencyDisplay').textContent = this.value + 'ms';
        };
        document.getElementById('inventoryError').oninput = function() {
            document.getElementById('inventoryErrorDisplay').textContent = this.value + '%';
        };
        document.getElementById('inventoryLatency').oninput = function() {
            document.getElementById('inventoryLatencyDisplay').textContent = this.value + 'ms';
        };

        function addLog(message, type = 'info') {
            const log = document.getElementById('activityLog');
            const entry = document.createElement('div');
            entry.className = `log-entry log-${type}`;
            entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
            log.insertBefore(entry, log.firstChild);
            if (log.children.length > 50) log.removeChild(log.lastChild);
        }

        async function injectChaos(service) {
            const port = service === 'payment' ? 3001 : 3002;
            const errorRate = parseFloat(document.getElementById(`${service}Error`).value) / 100;
            const latency = parseInt(document.getElementById(`${service}Latency`).value);

            try {
                await fetch(`http://localhost:${port}/chaos/config`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ enabled: true, errorRate, latency })
                });
                addLog(`Chaos injected into ${service}: ${(errorRate * 100).toFixed(0)}% errors, ${latency}ms latency`, 'warning');
            } catch (error) {
                addLog(`Failed to inject chaos into ${service}`, 'error');
            }
        }

        async function resetChaos() {
            try {
                await Promise.all([
                    fetch('http://localhost:3001/chaos/config', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ enabled: false, errorRate: 0, latency: 0 })
                    }),
                    fetch('http://localhost:3002/chaos/config', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ enabled: false, errorRate: 0, latency: 0 })
                    })
                ]);
                document.getElementById('paymentError').value = 0;
                document.getElementById('paymentLatency').value = 0;
                document.getElementById('inventoryError').value = 0;
                document.getElementById('inventoryLatency').value = 0;
                document.getElementById('paymentErrorDisplay').textContent = '0%';
                document.getElementById('paymentLatencyDisplay').textContent = '0ms';
                document.getElementById('inventoryErrorDisplay').textContent = '0%';
                document.getElementById('inventoryLatencyDisplay').textContent = '0ms';
                addLog('All chaos injection reset', 'success');
            } catch (error) {
                addLog('Failed to reset chaos', 'error');
            }
        }

        async function generateLoad() {
            const items = ['ITEM-001', 'ITEM-002', 'ITEM-003', 'ITEM-004', 'ITEM-005'];
            addLog('Generating load: 10 orders...', 'info');
            
            for (let i = 0; i < 10; i++) {
                const itemId = items[Math.floor(Math.random() * items.length)];
                fetch('/api/order', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        itemId,
                        quantity: Math.floor(Math.random() * 3) + 1,
                        paymentAmount: Math.random() * 1000 + 50
                    })
                }).then(res => res.json())
                  .then(data => {
                      if (data.success) {
                          addLog(`Order ${data.orderId} ${data.degraded ? 'accepted (degraded)' : 'successful'}`, data.degraded ? 'warning' : 'success');
                      } else {
                          addLog(`Order ${data.orderId} failed: ${data.error}`, 'error');
                      }
                  })
                  .catch(() => addLog('Order request failed', 'error'));
                
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        }

        async function updateMetrics() {
            try {
                const response = await fetch('/api/metrics');
                const data = await response.json();

                // Circuit Breakers
                const cbHTML = `
                    <div class="circuit-breaker">
                        <div style="display: flex; justify-content: space-between; align-items: center;">
                            <span style="font-weight: 600; color: #4a5568;">Payment Service</span>
                            <span class="circuit-state state-${data.frontend.circuitBreakers.payment.state.toLowerCase()}">${data.frontend.circuitBreakers.payment.state}</span>
                        </div>
                        <div style="margin-top: 8px; color: #718096; font-size: 0.9em;">
                            Failures: ${data.frontend.circuitBreakers.payment.failureCount}
                        </div>
                    </div>
                    <div class="circuit-breaker">
                        <div style="display: flex; justify-content: space-between; align-items: center;">
                            <span style="font-weight: 600; color: #4a5568;">Inventory Service</span>
                            <span class="circuit-state state-${data.frontend.circuitBreakers.inventory.state.toLowerCase()}">${data.frontend.circuitBreakers.inventory.state}</span>
                        </div>
                        <div style="margin-top: 8px; color: #718096; font-size: 0.9em;">
                            Failures: ${data.frontend.circuitBreakers.inventory.failureCount}
                        </div>
                    </div>
                `;
                document.getElementById('circuitBreakers').innerHTML = cbHTML;

                // Frontend Metrics
                const frontendHTML = `
                    <div class="metric">
                        <span class="metric-label">Total Orders</span>
                        <span class="metric-value">${data.frontend.totalOrders}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Successful</span>
                        <span class="metric-value" style="color: #48bb78;">${data.frontend.successfulOrders}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Degraded</span>
                        <span class="metric-value" style="color: #ed8936;">${data.frontend.degradedOrders}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Failed</span>
                        <span class="metric-value" style="color: #f56565;">${data.frontend.failedOrders}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Success Rate</span>
                        <span class="metric-value">${data.frontend.successRate}%</span>
                    </div>
                `;
                document.getElementById('frontendMetrics').innerHTML = frontendHTML;

                // Payment Metrics
                if (data.payment.error) {
                    document.getElementById('paymentMetrics').innerHTML = '<div class="status status-failed">Service Unavailable</div>';
                } else {
                    const paymentHTML = `
                        <div class="metric">
                            <span class="metric-label">Total Requests</span>
                            <span class="metric-value">${data.payment.totalRequests}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Successful</span>
                            <span class="metric-value" style="color: #48bb78;">${data.payment.successfulRequests}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Failed</span>
                            <span class="metric-value" style="color: #f56565;">${data.payment.failedRequests}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Success Rate</span>
                            <span class="metric-value">${data.payment.successRate}%</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Avg Latency</span>
                            <span class="metric-value">${data.payment.avgLatency.toFixed(2)}ms</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Chaos Status</span>
                            <span class="status ${data.payment.chaosConfig.enabled ? 'status-failed' : 'status-healthy'}">
                                ${data.payment.chaosConfig.enabled ? 'ACTIVE' : 'INACTIVE'}
                            </span>
                        </div>
                    `;
                    document.getElementById('paymentMetrics').innerHTML = paymentHTML;
                }

                // Inventory Metrics
                if (data.inventory.error) {
                    document.getElementById('inventoryMetrics').innerHTML = '<div class="status status-failed">Service Unavailable</div>';
                } else {
                    const inventoryHTML = `
                        <div class="metric">
                            <span class="metric-label">Total Requests</span>
                            <span class="metric-value">${data.inventory.totalRequests}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Successful</span>
                            <span class="metric-value" style="color: #48bb78;">${data.inventory.successfulRequests}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Failed</span>
                            <span class="metric-value" style="color: #f56565;">${data.inventory.failedRequests}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Success Rate</span>
                            <span class="metric-value">${data.inventory.successRate}%</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Avg Latency</span>
                            <span class="metric-value">${data.inventory.avgLatency.toFixed(2)}ms</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Chaos Status</span>
                            <span class="status ${data.inventory.chaosConfig.enabled ? 'status-failed' : 'status-healthy'}">
                                ${data.inventory.chaosConfig.enabled ? 'ACTIVE' : 'INACTIVE'}
                            </span>
                        </div>
                    `;
                    document.getElementById('inventoryMetrics').innerHTML = inventoryHTML;
                }
            } catch (error) {
                console.error('Failed to fetch metrics:', error);
            }
        }

        // Update metrics every 2 seconds
        setInterval(updateMetrics, 2000);
        updateMetrics();
    </script>
</body>
</html>
EOF

# 5. DOCKER COMPOSE
cat > chaos-demo/docker-compose.yml << 'EOF'
version: '3.8'

services:
  payment-service:
    build: ./payment-service
    container_name: payment-service
    ports:
      - "3001:3001"
    networks:
      - chaos-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3001/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  inventory-service:
    build: ./inventory-service
    container_name: inventory-service
    ports:
      - "3002:3002"
    networks:
      - chaos-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3002/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  frontend:
    build: ./frontend
    container_name: frontend
    ports:
      - "3000:3000"
    networks:
      - chaos-net
    depends_on:
      - payment-service
      - inventory-service
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  chaos-net:
    driver: bridge
EOF

# 6. DOCKERFILES
cat > chaos-demo/payment-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
RUN apk add --no-cache wget
EXPOSE 3001
CMD ["node", "server.js"]
EOF

cat > chaos-demo/inventory-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
RUN apk add --no-cache wget
EXPOSE 3002
CMD ["node", "server.js"]
EOF

cat > chaos-demo/frontend/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
COPY public ./public
RUN apk add --no-cache wget
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# 7. TEST SUITE
cat > chaos-demo/test.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Chaos Engineering Tests..."

# Test 1: Normal operation
echo "Test 1: Normal operation (no chaos)..."
for i in {1..5}; do
  response=$(curl -s -X POST http://localhost:3000/api/order \
    -H "Content-Type: application/json" \
    -d '{"itemId":"ITEM-001","quantity":1,"paymentAmount":999.99}')
  
  if echo "$response" | grep -q '"success":true'; then
    echo "✅ Order $i succeeded"
  else
    echo "❌ Order $i failed: $response"
  fi
done

# Test 2: Inject chaos into payment service
echo -e "\nTest 2: Payment service chaos (30% error rate)..."
curl -s -X POST http://localhost:3001/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"errorRate":0.3,"latency":0}' > /dev/null

sleep 2

success_count=0
for i in {1..10}; do
  response=$(curl -s -X POST http://localhost:3000/api/order \
    -H "Content-Type: application/json" \
    -d '{"itemId":"ITEM-002","quantity":1,"paymentAmount":29.99}')
  
  if echo "$response" | grep -q '"success":true'; then
    ((success_count++))
  fi
done

echo "✅ Success rate with chaos: $success_count/10 (expected ~7 due to retries and circuit breaker)"

# Test 3: High latency
echo -e "\nTest 3: High latency (2000ms)..."
curl -s -X POST http://localhost:3002/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"errorRate":0,"latency":2000}' > /dev/null

start_time=$(date +%s)
curl -s -X POST http://localhost:3000/api/order \
  -H "Content-Type: application/json" \
  -d '{"itemId":"ITEM-003","quantity":1,"paymentAmount":79.99}' > /dev/null
end_time=$(date +%s)

duration=$((end_time - start_time))
echo "✅ Request completed in ${duration}s (shows latency impact)"

# Test 4: Circuit breaker
echo -e "\nTest 4: Testing circuit breaker..."
curl -s -X POST http://localhost:3001/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"errorRate":1.0,"latency":0}' > /dev/null

echo "Triggering circuit breaker with 100% failure rate..."
for i in {1..5}; do
  curl -s -X POST http://localhost:3000/api/order \
    -H "Content-Type: application/json" \
    -d '{"itemId":"ITEM-004","quantity":1,"paymentAmount":299.99}' > /dev/null
  sleep 0.5
done

metrics=$(curl -s http://localhost:3000/api/metrics)
cb_state=$(echo "$metrics" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "✅ Circuit breaker state: $cb_state (expected OPEN)"

# Reset chaos
echo -e "\nResetting chaos configuration..."
curl -s -X POST http://localhost:3001/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":false,"errorRate":0,"latency":0}' > /dev/null

curl -s -X POST http://localhost:3002/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":false,"errorRate":0,"latency":0}' > /dev/null

echo -e "\n✅ All tests completed!"
EOF

chmod +x chaos-demo/test.sh

# 8. DEMO SCRIPT
cat > chaos-demo/demo.sh << 'EOF'
#!/bin/bash

echo "🎬 Chaos Engineering Demo"
echo "========================="
echo ""
echo "This demo shows chaos engineering in action with:"
echo "- Circuit breakers protecting against cascading failures"
echo "- Retry logic with exponential backoff"
echo "- Graceful degradation under failure conditions"
echo "- Real-time monitoring and metrics"
echo ""
echo "Dashboard: http://localhost:3000"
echo ""
echo "Try these experiments:"
echo "1. Generate normal load (no chaos)"
echo "2. Inject 30% errors into payment service and observe retries"
echo "3. Inject 100% errors to trigger circuit breaker"
echo "4. Add 2000ms latency to see timeout handling"
echo "5. Reset chaos and watch system recover"
echo ""
echo "Services:"
echo "- Frontend: http://localhost:3000"
echo "- Payment: http://localhost:3001"
echo "- Inventory: http://localhost:3002"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""

# Monitor logs
cd "$(dirname "$0")"
docker-compose logs -f
EOF

chmod +x chaos-demo/demo.sh

# 9. CLEANUP SCRIPT
cat > chaos-demo/cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Chaos Engineering Demo..."

cd "$(dirname "$0")"

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
EOF

chmod +x chaos-demo/cleanup.sh

# 10. BUILD AND RUN
cd chaos-demo

echo "🐳 Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check health
for service in frontend payment-service inventory-service; do
  status=$(docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null || echo "unknown")
  echo "$service: $status"
done

echo ""
echo "✅ Chaos Engineering Demo is ready!"
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo "📊 View real-time metrics and inject chaos experiments"
echo ""
echo "🧪 Run tests: bash test.sh"
echo "🎬 Run demo: bash demo.sh"
echo "🧹 Cleanup: bash cleanup.sh"
echo ""
echo "Try injecting chaos from the dashboard:"
echo "1. Set error rate or latency using sliders"
echo "2. Click 'Inject Chaos' to activate"
echo "3. Click 'Generate Load' to send test orders"
echo "4. Watch circuit breakers and resilience patterns in action"
EOF

chmod +x setup.sh

echo ""
echo "✅ Setup script created: setup.sh"
echo "Run: bash setup.sh"