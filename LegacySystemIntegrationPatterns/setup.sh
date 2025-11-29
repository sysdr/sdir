#!/bin/bash

set -e

echo "=========================================="
echo "Legacy System Integration Patterns Demo"
echo "=========================================="
echo ""

# Create project structure
mkdir -p legacy-integration-demo/{legacy-service,modern-services/{product,order,payment},acl-service,strangler-proxy,event-bus,dashboard}
cd legacy-integration-demo || exit 1

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: ecommerce
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data

  legacy-service:
    build: ./legacy-service
    ports:
      - "3001:3001"
    environment:
      - PORT=3001
      - DB_HOST=postgres
      - DB_USER=admin
      - DB_PASSWORD=password
      - DB_NAME=ecommerce
    depends_on:
      - postgres

  product-service:
    build: ./modern-services/product
    ports:
      - "3002:3002"
    environment:
      - PORT=3002
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis

  order-service:
    build: ./modern-services/order
    ports:
      - "3003:3003"
    environment:
      - PORT=3003
      - REDIS_URL=redis://redis:6379
      - DB_HOST=postgres
      - DB_USER=admin
      - DB_PASSWORD=password
      - DB_NAME=ecommerce
    depends_on:
      - postgres
      - redis

  payment-service:
    build: ./modern-services/payment
    ports:
      - "3004:3004"
    environment:
      - PORT=3004
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis

  acl-service:
    build: ./acl-service
    ports:
      - "3005:3005"
    environment:
      - PORT=3005
      - LEGACY_URL=http://legacy-service:3001
      - REDIS_URL=redis://redis:6379
    depends_on:
      - legacy-service
      - redis

  strangler-proxy:
    build: ./strangler-proxy
    ports:
      - "3000:3000"
    environment:
      - PORT=3000
      - LEGACY_URL=http://acl-service:3005
      - PRODUCT_URL=http://product-service:3002
      - ORDER_URL=http://order-service:3003
      - PAYMENT_URL=http://payment-service:3004
      - REDIS_URL=redis://redis:6379
    depends_on:
      - acl-service
      - product-service
      - order-service
      - payment-service
      - redis

  event-bus:
    build: ./event-bus
    ports:
      - "3006:3006"
    environment:
      - PORT=3006
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis

  dashboard:
    build: ./dashboard
    ports:
      - "3100:80"
    depends_on:
      - strangler-proxy

volumes:
  postgres-data:
EOF

# Legacy Service
mkdir -p legacy-service
cat > legacy-service/package.json << 'EOF'
{
  "name": "legacy-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "xml2js": "^0.6.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > legacy-service/server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const xml2js = require('xml2js');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.text({ type: 'text/xml' }));
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

// Initialize DB
(async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS legacy_orders (
      id SERIAL PRIMARY KEY,
      customer_name VARCHAR(255),
      product_code VARCHAR(100),
      quantity INTEGER,
      total_amount DECIMAL(10,2),
      status VARCHAR(50),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  console.log('Legacy database initialized');
})();

// SOAP-style XML endpoint (deliberately slow)
app.post('/soap/createOrder', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate legacy system slowness
  await new Promise(resolve => setTimeout(resolve, 2000 + Math.random() * 1000));
  
  try {
    const parser = new xml2js.Parser();
    const builder = new xml2js.Builder();
    
    const xmlData = await parser.parseStringPromise(req.body);
    const order = xmlData['soap:Envelope']['soap:Body'][0]['CreateOrderRequest'][0];
    
    const result = await pool.query(
      'INSERT INTO legacy_orders (customer_name, product_code, quantity, total_amount, status) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [order.CustomerName[0], order.ProductCode[0], order.Quantity[0], order.TotalAmount[0], 'PENDING']
    );
    
    const responseXml = {
      'soap:Envelope': {
        $: { 'xmlns:soap': 'http://schemas.xmlsoap.org/soap/envelope/' },
        'soap:Body': {
          CreateOrderResponse: {
            OrderId: result.rows[0].id,
            Status: 'SUCCESS',
            ProcessingTime: Date.now() - startTime
          }
        }
      }
    };
    
    res.set('Content-Type', 'text/xml');
    res.send(builder.buildObject(responseXml));
  } catch (error) {
    console.error('Legacy error:', error);
    res.status(500).send('<Error>Internal Server Error</Error>');
  }
});

// Get legacy orders
app.get('/legacy/orders', async (req, res) => {
  const result = await pool.query('SELECT * FROM legacy_orders ORDER BY created_at DESC LIMIT 20');
  res.json(result.rows);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'legacy', slow: true });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Legacy service running on port ${PORT}`);
});
EOF

cat > legacy-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Modern Product Service
mkdir -p modern-services/product
cat > modern-services/product/package.json << 'EOF'
{
  "name": "product-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.10",
    "cors": "^2.8.5"
  }
}
EOF

cat > modern-services/product/server.js << 'EOF'
const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect();

const products = {
  'PROD-001': { name: 'Laptop Pro', price: 1299.99, stock: 50 },
  'PROD-002': { name: 'Wireless Mouse', price: 29.99, stock: 200 },
  'PROD-003': { name: 'Mechanical Keyboard', price: 149.99, stock: 100 },
  'PROD-004': { name: '4K Monitor', price: 599.99, stock: 30 },
  'PROD-005': { name: 'USB-C Hub', price: 79.99, stock: 150 }
};

app.get('/products', async (req, res) => {
  const cached = await redisClient.get('products:all');
  if (cached) {
    return res.json({ ...JSON.parse(cached), cached: true });
  }
  
  await new Promise(resolve => setTimeout(resolve, 100));
  await redisClient.setEx('products:all', 60, JSON.stringify(products));
  res.json({ products, cached: false });
});

app.get('/products/:code', async (req, res) => {
  const product = products[req.params.code];
  if (!product) {
    return res.status(404).json({ error: 'Product not found' });
  }
  res.json(product);
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'product' });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`Product service running on port ${PORT}`);
});
EOF

cat > modern-services/product/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Modern Order Service
mkdir -p modern-services/order
cat > modern-services/order/package.json << 'EOF'
{
  "name": "order-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "redis": "^4.6.10",
    "cors": "^2.8.5"
  }
}
EOF

cat > modern-services/order/server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect();

(async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS modern_orders (
      id SERIAL PRIMARY KEY,
      customer_name VARCHAR(255),
      product_code VARCHAR(100),
      quantity INTEGER,
      total_amount DECIMAL(10,2),
      status VARCHAR(50),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  console.log('Modern orders table initialized');
})();

app.post('/orders', async (req, res) => {
  const startTime = Date.now();
  const { customerName, productCode, quantity, totalAmount } = req.body;
  
  try {
    const result = await pool.query(
      'INSERT INTO modern_orders (customer_name, product_code, quantity, total_amount, status) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [customerName, productCode, quantity, totalAmount, 'CONFIRMED']
    );
    
    // Publish event
    await redisClient.publish('order-events', JSON.stringify({
      type: 'ORDER_CREATED',
      orderId: result.rows[0].id,
      timestamp: new Date().toISOString()
    }));
    
    res.json({
      ...result.rows[0],
      processingTime: Date.now() - startTime,
      service: 'modern'
    });
  } catch (error) {
    console.error('Order error:', error);
    res.status(500).json({ error: 'Failed to create order' });
  }
});

app.get('/orders', async (req, res) => {
  const result = await pool.query('SELECT * FROM modern_orders ORDER BY created_at DESC LIMIT 20');
  res.json(result.rows);
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'order' });
});

const PORT = process.env.PORT || 3003;
app.listen(PORT, () => {
  console.log(`Order service running on port ${PORT}`);
});
EOF

cat > modern-services/order/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Modern Payment Service
mkdir -p modern-services/payment
cat > modern-services/payment/package.json << 'EOF'
{
  "name": "payment-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.10",
    "cors": "^2.8.5"
  }
}
EOF

cat > modern-services/payment/server.js << 'EOF'
const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect();

app.post('/payments', async (req, res) => {
  const { orderId, amount } = req.body;
  
  await new Promise(resolve => setTimeout(resolve, 200));
  
  const payment = {
    id: `PAY-${Date.now()}`,
    orderId,
    amount,
    status: 'PROCESSED',
    timestamp: new Date().toISOString()
  };
  
  await redisClient.publish('payment-events', JSON.stringify({
    type: 'PAYMENT_PROCESSED',
    ...payment
  }));
  
  res.json(payment);
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'payment' });
});

const PORT = process.env.PORT || 3004;
app.listen(PORT, () => {
  console.log(`Payment service running on port ${PORT}`);
});
EOF

cat > modern-services/payment/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Anti-Corruption Layer
mkdir -p acl-service
cat > acl-service/package.json << 'EOF'
{
  "name": "acl-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "xml2js": "^0.6.2",
    "redis": "^4.6.10",
    "cors": "^2.8.5"
  }
}
EOF

cat > acl-service/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const xml2js = require('xml2js');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect();

let stats = {
  totalRequests: 0,
  cacheHits: 0,
  translations: 0,
  avgLatency: 0
};

app.post('/legacy/orders', async (req, res) => {
  const startTime = Date.now();
  stats.totalRequests++;
  
  const { customerName, productCode, quantity, totalAmount } = req.body;
  
  // Check cache
  const cacheKey = `acl:${customerName}:${productCode}`;
  const cached = await redisClient.get(cacheKey);
  if (cached) {
    stats.cacheHits++;
    return res.json({ ...JSON.parse(cached), cached: true, latency: Date.now() - startTime });
  }
  
  try {
    // Transform REST to SOAP XML
    const builder = new xml2js.Builder();
    const soapRequest = builder.buildObject({
      'soap:Envelope': {
        $: { 'xmlns:soap': 'http://schemas.xmlsoap.org/soap/envelope/' },
        'soap:Body': {
          CreateOrderRequest: {
            CustomerName: customerName,
            ProductCode: productCode,
            Quantity: quantity,
            TotalAmount: totalAmount
          }
        }
      }
    });
    
    stats.translations++;
    
    // Call legacy service
    const response = await axios.post(
      `${process.env.LEGACY_URL}/soap/createOrder`,
      soapRequest,
      { headers: { 'Content-Type': 'text/xml' }, timeout: 5000 }
    );
    
    // Parse SOAP response
    const parser = new xml2js.Parser();
    const result = await parser.parseStringPromise(response.data);
    const orderData = result['soap:Envelope']['soap:Body'][0].CreateOrderResponse[0];
    
    // Transform to REST JSON
    const jsonResponse = {
      orderId: orderData.OrderId[0],
      status: orderData.Status[0],
      processingTime: parseInt(orderData.ProcessingTime[0]),
      service: 'legacy',
      translatedBy: 'ACL'
    };
    
    // Cache result
    await redisClient.setEx(cacheKey, 300, JSON.stringify(jsonResponse));
    
    const latency = Date.now() - startTime;
    stats.avgLatency = (stats.avgLatency * (stats.totalRequests - 1) + latency) / stats.totalRequests;
    
    res.json({ ...jsonResponse, cached: false, latency });
  } catch (error) {
    console.error('ACL error:', error.message);
    res.status(500).json({ 
      error: 'Translation failed', 
      details: error.message,
      circuitBreakerTripped: error.code === 'ETIMEDOUT'
    });
  }
});

app.get('/acl/stats', (req, res) => {
  res.json({
    ...stats,
    cacheHitRate: stats.totalRequests > 0 ? (stats.cacheHits / stats.totalRequests * 100).toFixed(2) + '%' : '0%'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'acl' });
});

const PORT = process.env.PORT || 3005;
app.listen(PORT, () => {
  console.log(`ACL service running on port ${PORT}`);
});
EOF

cat > acl-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Strangler Proxy
mkdir -p strangler-proxy
cat > strangler-proxy/package.json << 'EOF'
{
  "name": "strangler-proxy",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "redis": "^4.6.10",
    "cors": "^2.8.5",
    "ws": "^8.14.2"
  }
}
EOF

cat > strangler-proxy/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const { createClient } = require('redis');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.connect();

let trafficStats = {
  legacyCount: 0,
  modernCount: 0,
  totalRequests: 0
};

// Feature flags
let featureFlags = {
  modernOrdersPercentage: 10, // Start with 10% modern
  enableCaching: true,
  enableCircuitBreaker: true
};

// Broadcast stats to all connected clients
function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

// WebSocket connection
wss.on('connection', (ws) => {
  console.log('Dashboard connected');
  ws.send(JSON.stringify({ type: 'init', featureFlags, trafficStats }));
});

// Route decision logic
function shouldUseLegacy() {
  const rand = Math.random() * 100;
  return rand >= featureFlags.modernOrdersPercentage;
}

app.post('/api/orders', async (req, res) => {
  const startTime = Date.now();
  trafficStats.totalRequests++;
  
  const useLegacy = shouldUseLegacy();
  
  try {
    let response;
    if (useLegacy) {
      trafficStats.legacyCount++;
      response = await axios.post(
        `${process.env.LEGACY_URL}/legacy/orders`,
        req.body,
        { timeout: 6000 }
      );
      
      broadcast({
        type: 'request',
        route: 'legacy',
        latency: Date.now() - startTime,
        status: 'success',
        timestamp: new Date().toISOString()
      });
    } else {
      trafficStats.modernCount++;
      response = await axios.post(
        `${process.env.ORDER_URL}/orders`,
        req.body,
        { timeout: 2000 }
      );
      
      broadcast({
        type: 'request',
        route: 'modern',
        latency: Date.now() - startTime,
        status: 'success',
        timestamp: new Date().toISOString()
      });
    }
    
    res.json(response.data);
  } catch (error) {
    broadcast({
      type: 'request',
      route: useLegacy ? 'legacy' : 'modern',
      latency: Date.now() - startTime,
      status: 'error',
      timestamp: new Date().toISOString()
    });
    
    res.status(500).json({ error: error.message });
  }
});

// Get products (always modern)
app.get('/api/products', async (req, res) => {
  try {
    const response = await axios.get(`${process.env.PRODUCT_URL}/products`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get feature flags
app.get('/api/flags', (req, res) => {
  res.json(featureFlags);
});

// Update feature flags
app.post('/api/flags', (req, res) => {
  featureFlags = { ...featureFlags, ...req.body };
  broadcast({ type: 'flags', featureFlags });
  res.json(featureFlags);
});

// Get traffic stats
app.get('/api/stats', async (req, res) => {
  const aclStats = await axios.get(`${process.env.LEGACY_URL}/acl/stats`).catch(() => ({ data: {} }));
  
  res.json({
    traffic: trafficStats,
    acl: aclStats.data,
    distribution: {
      legacy: trafficStats.totalRequests > 0 ? 
        ((trafficStats.legacyCount / trafficStats.totalRequests) * 100).toFixed(1) : 0,
      modern: trafficStats.totalRequests > 0 ? 
        ((trafficStats.modernCount / trafficStats.totalRequests) * 100).toFixed(1) : 0
    }
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'strangler-proxy' });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Strangler proxy running on port ${PORT}`);
});
EOF

cat > strangler-proxy/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Event Bus
mkdir -p event-bus
cat > event-bus/package.json << 'EOF'
{
  "name": "event-bus",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.10",
    "cors": "^2.8.5",
    "ws": "^8.14.2"
  }
}
EOF

cat > event-bus/server.js << 'EOF'
const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const redisClient = createClient({ url: process.env.REDIS_URL });
const subscriber = redisClient.duplicate();

(async () => {
  await redisClient.connect();
  await subscriber.connect();
  
  await subscriber.subscribe('order-events', (message) => {
    console.log('Order event:', message);
    broadcast({ type: 'event', topic: 'orders', data: JSON.parse(message) });
  });
  
  await subscriber.subscribe('payment-events', (message) => {
    console.log('Payment event:', message);
    broadcast({ type: 'event', topic: 'payments', data: JSON.parse(message) });
  });
  
  console.log('Event bus subscribed to channels');
})();

function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

wss.on('connection', (ws) => {
  console.log('Event client connected');
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'event-bus' });
});

const PORT = process.env.PORT || 3006;
server.listen(PORT, () => {
  console.log(`Event bus running on port ${PORT}`);
});
EOF

cat > event-bus/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["node", "server.js"]
EOF

# Dashboard
mkdir -p dashboard/src dashboard/public
cat > dashboard/package.json << 'EOF'
{
  "name": "dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "recharts": "^2.10.3"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "browserslist": {
    "production": [">0.2%", "not dead"],
    "development": ["last 1 chrome version"]
  }
}
EOF

cat > dashboard/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
EOF

cat > dashboard/src/index.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

code {
  font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New', monospace;
}
EOF

cat > dashboard/src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import './App.css';

const COLORS = ['#8884d8', '#82ca9d', '#ffc658', '#ff7c7c'];

function App() {
  const [stats, setStats] = useState({ traffic: {}, acl: {}, distribution: {} });
  const [flags, setFlags] = useState({ modernOrdersPercentage: 10 });
  const [requests, setRequests] = useState([]);
  const [events, setEvents] = useState([]);
  const [products, setProducts] = useState([]);
  const [latencyData, setLatencyData] = useState([]);

  useEffect(() => {
    // Fetch initial data
    fetchStats();
    fetchFlags();
    fetchProducts();

    // WebSocket connection
    const ws = new WebSocket('ws://localhost:3000');
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      if (data.type === 'init') {
        setFlags(data.featureFlags);
        setStats({ traffic: data.trafficStats, acl: {}, distribution: {} });
      } else if (data.type === 'request') {
        setRequests(prev => [data, ...prev].slice(0, 10));
        setLatencyData(prev => [...prev, {
          time: new Date(data.timestamp).toLocaleTimeString(),
          latency: data.latency,
          route: data.route
        }].slice(-20));
      } else if (data.type === 'flags') {
        setFlags(data.featureFlags);
      }
    };

    // Poll stats
    const interval = setInterval(fetchStats, 2000);

    return () => {
      ws.close();
      clearInterval(interval);
    };
  }, []);

  const fetchStats = async () => {
    try {
      const response = await fetch('http://localhost:3000/api/stats');
      const data = await response.json();
      setStats(data);
    } catch (error) {
      console.error('Failed to fetch stats:', error);
    }
  };

  const fetchFlags = async () => {
    try {
      const response = await fetch('http://localhost:3000/api/flags');
      const data = await response.json();
      setFlags(data);
    } catch (error) {
      console.error('Failed to fetch flags:', error);
    }
  };

  const fetchProducts = async () => {
    try {
      const response = await fetch('http://localhost:3000/api/products');
      const data = await response.json();
      setProducts(Object.entries(data.products || {}).map(([code, info]) => ({ code, ...info })));
    } catch (error) {
      console.error('Failed to fetch products:', error);
    }
  };

  const updateFlag = async (key, value) => {
    try {
      await fetch('http://localhost:3000/api/flags', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [key]: value })
      });
      fetchFlags();
    } catch (error) {
      console.error('Failed to update flag:', error);
    }
  };

  const createOrder = async () => {
    const product = products[Math.floor(Math.random() * products.length)];
    if (!product) return;

    try {
      await fetch('http://localhost:3000/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          customerName: `Customer-${Math.floor(Math.random() * 1000)}`,
          productCode: product.code,
          quantity: Math.floor(Math.random() * 5) + 1,
          totalAmount: product.price
        })
      });
    } catch (error) {
      console.error('Failed to create order:', error);
    }
  };

  const pieData = [
    { name: 'Legacy', value: stats.traffic.legacyCount || 0 },
    { name: 'Modern', value: stats.traffic.modernCount || 0 }
  ];

  return (
    <div className="App">
      <header className="header">
        <h1>🔄 Legacy Integration Patterns Dashboard</h1>
        <p>Strangler Fig Pattern in Action</p>
      </header>

      <div className="container">
        {/* Control Panel */}
        <div className="card">
          <h2>⚙️ Control Panel</h2>
          <div className="controls">
            <div className="control-group">
              <label>Modern Traffic %: {flags.modernOrdersPercentage}%</label>
              <input
                type="range"
                min="0"
                max="100"
                step="10"
                value={flags.modernOrdersPercentage}
                onChange={(e) => updateFlag('modernOrdersPercentage', parseInt(e.target.value))}
              />
            </div>
            <button className="btn-primary" onClick={createOrder}>
              Create Test Order
            </button>
          </div>
        </div>

        {/* Stats Cards */}
        <div className="stats-grid">
          <div className="stat-card legacy">
            <h3>Legacy Requests</h3>
            <div className="stat-value">{stats.traffic.legacyCount || 0}</div>
            <div className="stat-label">{stats.distribution.legacy || 0}%</div>
          </div>
          <div className="stat-card modern">
            <h3>Modern Requests</h3>
            <div className="stat-value">{stats.traffic.modernCount || 0}</div>
            <div className="stat-label">{stats.distribution.modern || 0}%</div>
          </div>
          <div className="stat-card acl">
            <h3>ACL Cache Hit Rate</h3>
            <div className="stat-value">{stats.acl.cacheHitRate || '0%'}</div>
            <div className="stat-label">{stats.acl.cacheHits || 0} hits</div>
          </div>
          <div className="stat-card total">
            <h3>Total Requests</h3>
            <div className="stat-value">{stats.traffic.totalRequests || 0}</div>
            <div className="stat-label">All time</div>
          </div>
        </div>

        {/* Charts */}
        <div className="charts-grid">
          <div className="card">
            <h2>📊 Traffic Distribution</h2>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={pieData}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {pieData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>

          <div className="card">
            <h2>⏱️ Response Latency</h2>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={latencyData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis label={{ value: 'ms', angle: -90, position: 'insideLeft' }} />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="latency" stroke="#8884d8" strokeWidth={2} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Recent Requests */}
        <div className="card">
          <h2>📝 Recent Requests</h2>
          <div className="requests-list">
            {requests.map((req, idx) => (
              <div key={idx} className={`request-item ${req.route}`}>
                <span className="request-route">{req.route.toUpperCase()}</span>
                <span className="request-status">{req.status}</span>
                <span className="request-latency">{req.latency}ms</span>
                <span className="request-time">{new Date(req.timestamp).toLocaleTimeString()}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Products */}
        <div className="card">
          <h2>🛍️ Available Products (Modern Service)</h2>
          <div className="products-grid">
            {products.map(product => (
              <div key={product.code} className="product-card">
                <h3>{product.name}</h3>
                <p className="price">${product.price}</p>
                <p className="stock">Stock: {product.stock}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
EOF

cat > dashboard/src/App.css << 'EOF'
.App {
  min-height: 100vh;
  color: #ffffff;
}

.header {
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
  padding: 2rem;
  text-align: center;
  border-bottom: 2px solid rgba(255, 255, 255, 0.2);
}

.header h1 {
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
  text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
}

.container {
  max-width: 1400px;
  margin: 0 auto;
  padding: 2rem;
}

.card {
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  padding: 1.5rem;
  margin-bottom: 2rem;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
  color: #333;
}

.card h2 {
  margin-bottom: 1rem;
  color: #667eea;
}

.controls {
  display: flex;
  gap: 2rem;
  align-items: center;
  flex-wrap: wrap;
}

.control-group {
  flex: 1;
  min-width: 250px;
}

.control-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 600;
}

.control-group input[type="range"] {
  width: 100%;
}

.btn-primary {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  padding: 1rem 2rem;
  border-radius: 8px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: transform 0.2s;
}

.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1.5rem;
  margin-bottom: 2rem;
}

.stat-card {
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
  text-align: center;
}

.stat-card h3 {
  font-size: 0.9rem;
  color: #666;
  margin-bottom: 1rem;
}

.stat-value {
  font-size: 3rem;
  font-weight: 700;
  margin-bottom: 0.5rem;
}

.stat-label {
  color: #999;
  font-size: 0.9rem;
}

.stat-card.legacy .stat-value { color: #ff6b6b; }
.stat-card.modern .stat-value { color: #4ecdc4; }
.stat-card.acl .stat-value { color: #667eea; }
.stat-card.total .stat-value { color: #764ba2; }

.charts-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
  gap: 2rem;
  margin-bottom: 2rem;
}

.requests-list {
  max-height: 400px;
  overflow-y: auto;
}

.request-item {
  display: flex;
  gap: 1rem;
  padding: 1rem;
  border-bottom: 1px solid #eee;
  align-items: center;
}

.request-route {
  font-weight: 700;
  padding: 0.25rem 0.75rem;
  border-radius: 4px;
}

.request-item.legacy .request-route {
  background: #ffe5e5;
  color: #ff6b6b;
}

.request-item.modern .request-route {
  background: #e5f9f7;
  color: #4ecdc4;
}

.request-status {
  padding: 0.25rem 0.75rem;
  border-radius: 4px;
  background: #e8f5e9;
  color: #2e7d32;
}

.request-latency {
  font-weight: 600;
  color: #667eea;
}

.request-time {
  color: #999;
  font-size: 0.9rem;
  margin-left: auto;
}

.products-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 1rem;
}

.product-card {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 1.5rem;
  border-radius: 8px;
  text-align: center;
}

.product-card h3 {
  margin-bottom: 0.5rem;
  font-size: 1.1rem;
}

.product-card .price {
  font-size: 1.5rem;
  font-weight: 700;
  margin: 0.5rem 0;
}

.product-card .stock {
  opacity: 0.9;
  font-size: 0.9rem;
}
EOF

cat > dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Legacy Integration Dashboard</title>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:18-alpine as build
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

cat > dashboard/.dockerignore << 'EOF'
node_modules
build
EOF

# Go back to root directory to create scripts
cd ..

# Create demo.sh script
cat > demo.sh << 'EOF'
#!/bin/bash

set -e

echo "=========================================="
echo "Building Docker images..."
echo "=========================================="
cd legacy-integration-demo
docker-compose build

echo ""
echo "=========================================="
echo "Starting services..."
echo "=========================================="
docker-compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 15

echo ""
echo "=========================================="
echo "✅ Demo is ready!"
echo "=========================================="
echo ""
echo "🌐 Dashboard: http://localhost:3100"
echo "🔄 Strangler Proxy: http://localhost:3000"
echo "📊 ACL Stats: http://localhost:3005/acl/stats"
echo "🏪 Products API: http://localhost:3000/api/products"
echo ""
echo "=========================================="
echo "Try these experiments:"
echo "=========================================="
echo "1. Open dashboard and click 'Create Test Order' multiple times"
echo "2. Adjust the 'Modern Traffic %' slider to see routing change"
echo "3. Watch latency differences between Legacy and Modern routes"
echo "4. Observe ACL cache hit rate improving over time"
echo "5. Set Modern Traffic to 100% to complete strangler pattern"
echo ""
echo "Service Logs:"
echo "  docker-compose logs -f strangler-proxy"
echo "  docker-compose logs -f acl-service"
echo "  docker-compose logs -f legacy-service"
echo ""
echo "To clean up, run: ./cleanup.sh"
EOF

chmod +x demo.sh

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "Stopping and removing all containers..."
cd legacy-integration-demo
docker-compose down -v

echo "Cleaning up..."
cd ..
rm -rf legacy-integration-demo

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

echo ""
echo "=========================================="
echo "Files created successfully!"
echo "=========================================="
echo ""
echo "To run the demo:"
echo "  ./demo.sh"
echo ""
echo "To cleanup:"
echo "  ./cleanup.sh"
echo ""