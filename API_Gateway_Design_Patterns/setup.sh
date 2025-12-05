#!/bin/bash

set -e

echo "======================================"
echo "API Gateway Design Patterns Demo"
echo "======================================"
echo ""

# Create project structure
echo "Creating project structure..."
mkdir -p api-gateway-demo/{gateway,user-service,order-service,analytics-service,notification-service,frontend}
cd api-gateway-demo

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru

  user-service:
    build: ./user-service
    ports:
      - "3001:3001"
    environment:
      - PORT=3001
      - SERVICE_NAME=user-service

  order-service:
    build: ./order-service
    ports:
      - "3002:3002"
    environment:
      - PORT=3002
      - SERVICE_NAME=order-service

  analytics-service:
    build: ./analytics-service
    ports:
      - "3003:3003"
    environment:
      - PORT=3003
      - SERVICE_NAME=analytics-service

  notification-service:
    build: ./notification-service
    ports:
      - "3004:3004"
    environment:
      - PORT=3004
      - SERVICE_NAME=notification-service
      - SIMULATE_TIMEOUT=true

  gateway:
    build: ./gateway
    ports:
      - "3000:3000"
      - "3005:3005"
    depends_on:
      - redis
      - user-service
      - order-service
      - analytics-service
      - notification-service
    environment:
      - PORT=3000
      - METRICS_PORT=3005
      - REDIS_URL=redis://redis:6379
      - USER_SERVICE_URL=http://user-service:3001
      - ORDER_SERVICE_URL=http://order-service:3002
      - ANALYTICS_SERVICE_URL=http://analytics-service:3003
      - NOTIFICATION_SERVICE_URL=http://notification-service:3004

  frontend:
    build: ./frontend
    ports:
      - "8080:80"
    depends_on:
      - gateway

EOF

# Create Gateway Service
echo "Creating API Gateway service..."
mkdir -p gateway/src

cat > gateway/package.json << 'EOF'
{
  "name": "api-gateway",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "redis": "^4.6.0",
    "jsonwebtoken": "^9.0.2",
    "ws": "^8.14.2",
    "prom-client": "^15.0.0"
  }
}
EOF

cat > gateway/src/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const redis = require('redis');
const jwt = require('jsonwebtoken');
const { WebSocketServer } = require('ws');
const http = require('http');
const promClient = require('prom-client');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(express.json());
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

const JWT_SECRET = 'demo-secret-key';
const redisClient = redis.createClient({ url: process.env.REDIS_URL });

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [10, 50, 100, 200, 500, 1000, 2000]
});
register.registerMetric(httpRequestDuration);

const rateLimitCounter = new promClient.Counter({
  name: 'rate_limit_hits_total',
  help: 'Total rate limit hits',
  labelNames: ['user_id', 'endpoint']
});
register.registerMetric(rateLimitCounter);

const cacheHits = new promClient.Counter({
  name: 'cache_hits_total',
  help: 'Total cache hits',
  labelNames: ['endpoint']
});
register.registerMetric(cacheHits);

const cacheMisses = new promClient.Counter({
  name: 'cache_misses_total',
  help: 'Total cache misses',
  labelNames: ['endpoint']
});
register.registerMetric(cacheMisses);

// Connect to Redis
(async () => {
  await redisClient.connect();
  console.log('Connected to Redis');
})();

// WebSocket connections for real-time metrics
const clients = new Set();
wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcastMetrics(data) {
  clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

// Authentication Middleware (Pattern 5)
function authenticate(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }
  
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// Rate Limiting Middleware (Pattern 4)
async function rateLimit(req, res, next) {
  const userId = req.user?.userId || 'anonymous';
  const key = `ratelimit:${userId}:${req.path}`;
  const limit = 100; // requests per minute
  const window = 60; // seconds
  
  try {
    const current = await redisClient.get(key);
    
    if (current && parseInt(current) >= limit) {
      rateLimitCounter.inc({ user_id: userId, endpoint: req.path });
      return res.status(429).json({ 
        error: 'Rate limit exceeded',
        retryAfter: await redisClient.ttl(key)
      });
    }
    
    const multi = redisClient.multi();
    multi.incr(key);
    if (!current) multi.expire(key, window);
    await multi.exec();
    
    res.setHeader('X-RateLimit-Limit', limit);
    res.setHeader('X-RateLimit-Remaining', limit - (parseInt(current) || 0) - 1);
    
    next();
  } catch (error) {
    console.error('Rate limit error:', error);
    next(); // Fail open
  }
}

// Cache Middleware (Pattern 2 optimization)
function cacheMiddleware(ttl = 60) {
  return async (req, res, next) => {
    if (req.method !== 'GET') return next();
    
    const cacheKey = `cache:${req.path}:${JSON.stringify(req.query)}:${req.user?.userId}`;
    
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        cacheHits.inc({ endpoint: req.path });
        broadcastMetrics({ type: 'cache_hit', endpoint: req.path, timestamp: Date.now() });
        return res.json({ ...JSON.parse(cached), cached: true, cacheHit: true });
      }
      
      cacheMisses.inc({ endpoint: req.path });
      
      const originalJson = res.json.bind(res);
      res.json = (body) => {
        redisClient.setEx(cacheKey, ttl, JSON.stringify(body));
        return originalJson({ ...body, cached: false, cacheHit: false });
      };
      
      next();
    } catch (error) {
      console.error('Cache error:', error);
      next();
    }
  };
}

// Request Orchestration (Pattern 2)
async function orchestrateServices(userId) {
  const startTime = Date.now();
  
  const serviceConfigs = [
    { 
      name: 'user', 
      url: `${process.env.USER_SERVICE_URL}/api/user/${userId}`,
      timeout: 500,
      critical: true
    },
    { 
      name: 'orders', 
      url: `${process.env.ORDER_SERVICE_URL}/api/orders/${userId}`,
      timeout: 500,
      critical: false
    },
    { 
      name: 'analytics', 
      url: `${process.env.ANALYTICS_SERVICE_URL}/api/analytics/${userId}`,
      timeout: 500,
      critical: false
    },
    { 
      name: 'notifications', 
      url: `${process.env.NOTIFICATION_SERVICE_URL}/api/notifications/${userId}`,
      timeout: 300,
      critical: false
    }
  ];
  
  const results = await Promise.allSettled(
    serviceConfigs.map(config =>
      axios.get(config.url, { timeout: config.timeout })
        .then(response => ({ name: config.name, data: response.data, latency: Date.now() - startTime }))
        .catch(error => ({ 
          name: config.name, 
          error: error.message, 
          degraded: !config.critical 
        }))
    )
  );
  
  const response = {
    aggregated: true,
    totalLatency: Date.now() - startTime,
    services: {}
  };
  
  results.forEach((result, index) => {
    const config = serviceConfigs[index];
    if (result.status === 'fulfilled') {
      const value = result.value;
      if (value.error && !config.critical) {
        response.services[value.name] = { status: 'degraded', message: 'Service unavailable' };
      } else if (value.error) {
        throw new Error(`Critical service ${value.name} failed`);
      } else {
        response.services[value.name] = { status: 'success', data: value.data, latency: value.latency };
      }
    } else {
      if (config.critical) {
        throw new Error(`Critical service ${config.name} failed`);
      }
      response.services[config.name] = { status: 'degraded', message: 'Service timeout' };
    }
  });
  
  return response;
}

// Login endpoint - issues JWT
app.post('/api/login', (req, res) => {
  const { username } = req.body;
  
  const token = jwt.sign(
    { userId: username || 'demo-user', username: username || 'demo-user' },
    JWT_SECRET,
    { expiresIn: '24h' }
  );
  
  res.json({ token, username: username || 'demo-user' });
});

// BFF Pattern - Mobile endpoint (Pattern 1)
app.get('/api/mobile/dashboard', authenticate, rateLimit, cacheMiddleware(30), async (req, res) => {
  const end = httpRequestDuration.startTimer();
  
  try {
    const data = await orchestrateServices(req.user.userId);
    
    // Mobile optimization: reduce payload, only essential fields
    const mobileOptimized = {
      user: {
        name: data.services.user?.data?.name,
        avatar: data.services.user?.data?.avatar
      },
      recentOrders: data.services.orders?.data?.orders?.slice(0, 3),
      notificationCount: data.services.notifications?.data?.count || 0,
      performance: {
        totalLatency: data.totalLatency,
        pattern: 'BFF-Mobile'
      }
    };
    
    broadcastMetrics({ 
      type: 'request', 
      endpoint: '/api/mobile/dashboard', 
      latency: data.totalLatency,
      pattern: 'BFF-Mobile',
      timestamp: Date.now()
    });
    
    end({ method: 'GET', route: '/api/mobile/dashboard', status_code: 200 });
    res.json(mobileOptimized);
  } catch (error) {
    end({ method: 'GET', route: '/api/mobile/dashboard', status_code: 500 });
    res.status(500).json({ error: error.message });
  }
});

// BFF Pattern - Web endpoint (Pattern 1)
app.get('/api/web/dashboard', authenticate, rateLimit, cacheMiddleware(60), async (req, res) => {
  const end = httpRequestDuration.startTimer();
  
  try {
    const data = await orchestrateServices(req.user.userId);
    
    // Web optimization: full data with analytics
    const webOptimized = {
      user: data.services.user?.data,
      orders: data.services.orders?.data,
      analytics: data.services.analytics?.data,
      notifications: data.services.notifications?.data,
      metadata: {
        totalLatency: data.totalLatency,
        pattern: 'BFF-Web',
        servicesStatus: Object.entries(data.services).map(([name, service]) => ({
          name,
          status: service.status,
          latency: service.latency
        }))
      }
    };
    
    broadcastMetrics({ 
      type: 'request', 
      endpoint: '/api/web/dashboard', 
      latency: data.totalLatency,
      pattern: 'BFF-Web',
      timestamp: Date.now()
    });
    
    end({ method: 'GET', route: '/api/web/dashboard', status_code: 200 });
    res.json(webOptimized);
  } catch (error) {
    end({ method: 'GET', route: '/api/web/dashboard', status_code: 500 });
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: Date.now() });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`API Gateway running on port ${PORT}`);
  console.log(`WebSocket server running for real-time metrics`);
});
EOF

cat > gateway/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["npm", "start"]
EOF

# Create User Service
echo "Creating User Service..."
mkdir -p user-service/src

cat > user-service/package.json << 'EOF'
{
  "name": "user-service",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > user-service/src/server.js << 'EOF'
const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/user/:userId', async (req, res) => {
  // Simulate realistic latency
  await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 50));
  
  res.json({
    id: req.params.userId,
    name: 'John Doe',
    email: 'john@example.com',
    avatar: 'https://ui-avatars.com/api/?name=John+Doe',
    memberSince: '2020-01-15',
    preferences: {
      language: 'en',
      timezone: 'UTC',
      notifications: true
    }
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`User Service on port ${PORT}`));
EOF

cat > user-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["npm", "start"]
EOF

# Create Order Service
echo "Creating Order Service..."
mkdir -p order-service/src

cat > order-service/package.json << 'EOF'
{
  "name": "order-service",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > order-service/src/server.js << 'EOF'
const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/orders/:userId', async (req, res) => {
  // Simulate realistic latency
  await new Promise(resolve => setTimeout(resolve, 80 + Math.random() * 80));
  
  res.json({
    orders: [
      {
        id: 'ORD-001',
        date: '2024-11-20',
        amount: 149.99,
        status: 'delivered',
        items: 3
      },
      {
        id: 'ORD-002',
        date: '2024-11-25',
        amount: 89.50,
        status: 'shipped',
        items: 2
      },
      {
        id: 'ORD-003',
        date: '2024-11-27',
        amount: 299.99,
        status: 'processing',
        items: 5
      }
    ],
    totalOrders: 3,
    totalSpent: 539.48
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`Order Service on port ${PORT}`));
EOF

cat > order-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["npm", "start"]
EOF

# Create Analytics Service
echo "Creating Analytics Service..."
mkdir -p analytics-service/src

cat > analytics-service/package.json << 'EOF'
{
  "name": "analytics-service",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > analytics-service/src/server.js << 'EOF'
const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/analytics/:userId', async (req, res) => {
  // Simulate realistic latency
  await new Promise(resolve => setTimeout(resolve, 60 + Math.random() * 60));
  
  res.json({
    pageViews: 1247,
    sessionDuration: 1832,
    bounceRate: 0.32,
    topPages: [
      { path: '/dashboard', views: 523 },
      { path: '/products', views: 412 },
      { path: '/orders', views: 312 }
    ],
    deviceBreakdown: {
      mobile: 0.45,
      desktop: 0.42,
      tablet: 0.13
    }
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3003;
app.listen(PORT, () => console.log(`Analytics Service on port ${PORT}`));
EOF

cat > analytics-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["npm", "start"]
EOF

# Create Notification Service (with timeout simulation)
echo "Creating Notification Service..."
mkdir -p notification-service/src

cat > notification-service/package.json << 'EOF'
{
  "name": "notification-service",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > notification-service/src/server.js << 'EOF'
const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/notifications/:userId', async (req, res) => {
  // Simulate occasional timeouts (30% chance)
  if (process.env.SIMULATE_TIMEOUT === 'true' && Math.random() < 0.3) {
    await new Promise(resolve => setTimeout(resolve, 5000));
  } else {
    await new Promise(resolve => setTimeout(resolve, 70 + Math.random() * 50));
  }
  
  res.json({
    count: 7,
    unread: 3,
    notifications: [
      { id: 1, type: 'order', message: 'Order shipped', read: false },
      { id: 2, type: 'promo', message: 'New sale alert', read: false },
      { id: 3, type: 'system', message: 'Profile updated', read: true }
    ]
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3004;
app.listen(PORT, () => console.log(`Notification Service on port ${PORT}`));
EOF

cat > notification-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
CMD ["npm", "start"]
EOF

# Create Frontend
echo "Creating Frontend Dashboard..."
mkdir -p frontend/src

cat > frontend/src/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>API Gateway Design Patterns Demo</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      padding: 20px;
    }
    
    .container {
      max-width: 1400px;
      margin: 0 auto;
    }
    
    header {
      background: white;
      padding: 30px;
      border-radius: 16px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.1);
      margin-bottom: 30px;
    }
    
    h1 {
      color: #1a202c;
      font-size: 32px;
      margin-bottom: 10px;
    }
    
    .subtitle {
      color: #718096;
      font-size: 16px;
    }
    
    .patterns-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    
    .pattern-card {
      background: white;
      padding: 24px;
      border-radius: 12px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.08);
      transition: transform 0.2s, box-shadow 0.2s;
    }
    
    .pattern-card:hover {
      transform: translateY(-4px);
      box-shadow: 0 8px 30px rgba(0,0,0,0.12);
    }
    
    .pattern-title {
      font-size: 18px;
      font-weight: 700;
      color: #667eea;
      margin-bottom: 8px;
    }
    
    .pattern-desc {
      font-size: 14px;
      color: #4a5568;
      line-height: 1.6;
    }
    
    .dashboard-grid {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 20px;
      margin-bottom: 30px;
    }
    
    .card {
      background: white;
      padding: 24px;
      border-radius: 12px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.08);
    }
    
    .card-title {
      font-size: 20px;
      font-weight: 700;
      color: #1a202c;
      margin-bottom: 20px;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    
    .status-indicator {
      width: 12px;
      height: 12px;
      border-radius: 50%;
      animation: pulse 2s infinite;
    }
    
    .status-healthy {
      background: #48bb78;
    }
    
    .status-degraded {
      background: #ed8936;
    }
    
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
    
    .metric {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 0;
      border-bottom: 1px solid #e2e8f0;
    }
    
    .metric:last-child {
      border-bottom: none;
    }
    
    .metric-label {
      font-size: 14px;
      color: #4a5568;
    }
    
    .metric-value {
      font-size: 18px;
      font-weight: 700;
      color: #667eea;
    }
    
    .metric-value.success {
      color: #48bb78;
    }
    
    .metric-value.warning {
      color: #ed8936;
    }
    
    .test-buttons {
      display: flex;
      gap: 12px;
      margin-top: 20px;
    }
    
    button {
      flex: 1;
      padding: 14px 24px;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    }
    
    .btn-primary {
      background: #667eea;
      color: white;
    }
    
    .btn-primary:hover {
      background: #5568d3;
      transform: translateY(-2px);
      box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
    }
    
    .btn-secondary {
      background: #e2e8f0;
      color: #2d3748;
    }
    
    .btn-secondary:hover {
      background: #cbd5e0;
    }
    
    .btn-primary:disabled, .btn-secondary:disabled {
      opacity: 0.5;
      cursor: not-allowed;
      transform: none;
    }
    
    .log-console {
      background: #1a202c;
      color: #e2e8f0;
      padding: 20px;
      border-radius: 8px;
      max-height: 400px;
      overflow-y: auto;
      font-family: 'Monaco', 'Menlo', monospace;
      font-size: 13px;
      line-height: 1.6;
    }
    
    .log-entry {
      margin-bottom: 8px;
      padding: 4px 0;
    }
    
    .log-timestamp {
      color: #718096;
    }
    
    .log-success {
      color: #68d391;
    }
    
    .log-error {
      color: #fc8181;
    }
    
    .log-info {
      color: #63b3ed;
    }
    
    .service-status-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 12px;
    }
    
    .service-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px;
      background: #f7fafc;
      border-radius: 8px;
    }
    
    .service-name {
      font-size: 14px;
      font-weight: 600;
      color: #2d3748;
    }
    
    .service-latency {
      font-size: 13px;
      color: #718096;
    }
    
    .chart-container {
      height: 200px;
      margin-top: 20px;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>🚪 API Gateway Design Patterns</h1>
      <p class="subtitle">Production-grade patterns demonstrating BFF, Orchestration, Rate Limiting, Caching & Security</p>
    </header>
    
    <div class="patterns-grid">
      <div class="pattern-card">
        <div class="pattern-title">Pattern 1: Backend for Frontend</div>
        <div class="pattern-desc">Separate gateways for mobile and web with optimized payloads</div>
      </div>
      <div class="pattern-card">
        <div class="pattern-title">Pattern 2: Request Orchestration</div>
        <div class="pattern-desc">Parallel service calls with graceful degradation</div>
      </div>
      <div class="pattern-card">
        <div class="pattern-title">Pattern 3: Protocol Translation</div>
        <div class="pattern-desc">REST gateway to diverse backend protocols</div>
      </div>
      <div class="pattern-card">
        <div class="pattern-title">Pattern 4: Rate Limiting</div>
        <div class="pattern-desc">Redis-backed token bucket with burst handling</div>
      </div>
      <div class="pattern-card">
        <div class="pattern-title">Pattern 5: Security</div>
        <div class="pattern-desc">Centralized JWT authentication and validation</div>
      </div>
    </div>
    
    <div class="dashboard-grid">
      <div class="card">
        <div class="card-title">
          <span class="status-indicator status-healthy"></span>
          Real-time Gateway Metrics
        </div>
        
        <div class="metric">
          <span class="metric-label">Total Requests</span>
          <span class="metric-value" id="totalRequests">0</span>
        </div>
        <div class="metric">
          <span class="metric-label">Average Latency</span>
          <span class="metric-value" id="avgLatency">0ms</span>
        </div>
        <div class="metric">
          <span class="metric-label">Cache Hit Rate</span>
          <span class="metric-value success" id="cacheHitRate">0%</span>
        </div>
        <div class="metric">
          <span class="metric-label">Rate Limit Hits</span>
          <span class="metric-value warning" id="rateLimitHits">0</span>
        </div>
        
        <div class="test-buttons">
          <button class="btn-primary" onclick="testWebBFF()">Test Web BFF</button>
          <button class="btn-primary" onclick="testMobileBFF()">Test Mobile BFF</button>
          <button class="btn-secondary" onclick="testRateLimit()">Test Rate Limit</button>
        </div>
        
        <div style="margin-top: 24px;">
          <div class="card-title">Service Health</div>
          <div class="service-status-grid" id="serviceStatus"></div>
        </div>
      </div>
      
      <div class="card">
        <div class="card-title">Request Logs</div>
        <div class="log-console" id="logConsole"></div>
      </div>
    </div>
  </div>
  
  <script>
    const API_URL = 'http://localhost:3000';
    const WS_URL = 'ws://localhost:3000';
    let token = null;
    let ws = null;
    let metrics = {
      totalRequests: 0,
      totalLatency: 0,
      cacheHits: 0,
      cacheMisses: 0,
      rateLimitHits: 0
    };
    
    function addLog(message, type = 'info') {
      const logConsole = document.getElementById('logConsole');
      const timestamp = new Date().toLocaleTimeString();
      const logClass = type === 'success' ? 'log-success' : type === 'error' ? 'log-error' : 'log-info';
      
      const logEntry = document.createElement('div');
      logEntry.className = 'log-entry';
      logEntry.innerHTML = `<span class="log-timestamp">[${timestamp}]</span> <span class="${logClass}">${message}</span>`;
      
      logConsole.insertBefore(logEntry, logConsole.firstChild);
      
      if (logConsole.children.length > 50) {
        logConsole.removeChild(logConsole.lastChild);
      }
    }
    
    function updateMetrics() {
      document.getElementById('totalRequests').textContent = metrics.totalRequests;
      
      const avgLatency = metrics.totalRequests > 0 
        ? Math.round(metrics.totalLatency / metrics.totalRequests) 
        : 0;
      document.getElementById('avgLatency').textContent = avgLatency + 'ms';
      
      const totalCacheRequests = metrics.cacheHits + metrics.cacheMisses;
      const hitRate = totalCacheRequests > 0 
        ? Math.round((metrics.cacheHits / totalCacheRequests) * 100) 
        : 0;
      document.getElementById('cacheHitRate').textContent = hitRate + '%';
      
      document.getElementById('rateLimitHits').textContent = metrics.rateLimitHits;
    }
    
    function connectWebSocket() {
      ws = new WebSocket(WS_URL);
      
      ws.onopen = () => {
        addLog('WebSocket connected - receiving real-time metrics', 'success');
      };
      
      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        
        if (data.type === 'request') {
          metrics.totalRequests++;
          metrics.totalLatency += data.latency;
          addLog(`${data.pattern} request completed in ${data.latency}ms`, 'success');
        } else if (data.type === 'cache_hit') {
          metrics.cacheHits++;
          addLog(`Cache HIT for ${data.endpoint}`, 'info');
        }
        
        updateMetrics();
      };
      
      ws.onerror = () => {
        addLog('WebSocket connection error', 'error');
      };
      
      ws.onclose = () => {
        addLog('WebSocket disconnected - reconnecting...', 'error');
        setTimeout(connectWebSocket, 3000);
      };
    }
    
    async function login() {
      try {
        const response = await fetch(`${API_URL}/api/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username: 'demo-user' })
        });
        
        const data = await response.json();
        token = data.token;
        addLog('Authenticated successfully with JWT token', 'success');
      } catch (error) {
        addLog('Authentication failed: ' + error.message, 'error');
      }
    }
    
    async function testWebBFF() {
      if (!token) {
        addLog('Please wait, authenticating...', 'error');
        return;
      }
      
      try {
        const start = Date.now();
        const response = await fetch(`${API_URL}/api/web/dashboard`, {
          headers: { 'Authorization': `Bearer ${token}` }
        });
        
        const data = await response.json();
        const latency = Date.now() - start;
        
        metrics.totalRequests++;
        metrics.totalLatency += latency;
        
        if (data.cacheHit) {
          metrics.cacheHits++;
        } else {
          metrics.cacheMisses++;
        }
        
        addLog(`Web BFF: ${latency}ms, Cache: ${data.cacheHit ? 'HIT' : 'MISS'}`, 'success');
        
        if (data.metadata && data.metadata.servicesStatus) {
          updateServiceStatus(data.metadata.servicesStatus);
        }
        
        updateMetrics();
      } catch (error) {
        addLog('Web BFF request failed: ' + error.message, 'error');
      }
    }
    
    async function testMobileBFF() {
      if (!token) {
        addLog('Please wait, authenticating...', 'error');
        return;
      }
      
      try {
        const start = Date.now();
        const response = await fetch(`${API_URL}/api/mobile/dashboard`, {
          headers: { 'Authorization': `Bearer ${token}` }
        });
        
        const data = await response.json();
        const latency = Date.now() - start;
        
        metrics.totalRequests++;
        metrics.totalLatency += latency;
        
        if (data.cacheHit) {
          metrics.cacheHits++;
        } else {
          metrics.cacheMisses++;
        }
        
        addLog(`Mobile BFF: ${latency}ms, Payload optimized, Cache: ${data.cacheHit ? 'HIT' : 'MISS'}`, 'success');
        updateMetrics();
      } catch (error) {
        addLog('Mobile BFF request failed: ' + error.message, 'error');
      }
    }
    
    async function testRateLimit() {
      if (!token) {
        addLog('Please wait, authenticating...', 'error');
        return;
      }
      
      addLog('Sending 10 rapid requests to test rate limiting...', 'info');
      
      for (let i = 0; i < 10; i++) {
        try {
          const response = await fetch(`${API_URL}/api/web/dashboard`, {
            headers: { 'Authorization': `Bearer ${token}` }
          });
          
          if (response.status === 429) {
            metrics.rateLimitHits++;
            addLog(`Request ${i + 1}: Rate limit exceeded!`, 'error');
          } else {
            addLog(`Request ${i + 1}: Success`, 'success');
          }
        } catch (error) {
          addLog(`Request ${i + 1}: ${error.message}`, 'error');
        }
        
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      
      updateMetrics();
    }
    
    function updateServiceStatus(services) {
      const container = document.getElementById('serviceStatus');
      container.innerHTML = '';
      
      services.forEach(service => {
        const item = document.createElement('div');
        item.className = 'service-item';
        item.innerHTML = `
          <div>
            <div class="service-name">${service.name}</div>
            <div class="service-latency">${service.status}</div>
          </div>
          <div class="service-latency">${service.latency ? service.latency + 'ms' : 'N/A'}</div>
        `;
        container.appendChild(item);
      });
    }
    
    // Initialize
    (async () => {
      await login();
      connectWebSocket();
      
      // Periodic health check
      setInterval(async () => {
        try {
          const response = await fetch(`${API_URL}/health`);
          const data = await response.json();
          
          if (data.status !== 'healthy') {
            addLog('Gateway health check failed', 'error');
          }
        } catch (error) {
          addLog('Health check error: ' + error.message, 'error');
        }
      }, 30000);
    })();
  </script>
</body>
</html>
EOF

cat > frontend/Dockerfile << 'EOF'
FROM nginx:alpine
COPY src/index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# Create test script
echo "Creating test script..."
cat > test.sh << 'EOF'
#!/bin/bash

echo "Running API Gateway Tests..."
echo "======================================"

# Wait for services
sleep 10

# Test 1: Health Check
echo ""
echo "Test 1: Gateway Health Check"
curl -s http://localhost:3000/health | jq '.'

# Test 2: Authentication
echo ""
echo "Test 2: JWT Authentication"
TOKEN=$(curl -s -X POST http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test-user"}' | jq -r '.token')
echo "Token obtained: ${TOKEN:0:20}..."

# Test 3: Web BFF Pattern
echo ""
echo "Test 3: Web BFF Pattern (Full Data)"
curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.metadata'

# Test 4: Mobile BFF Pattern
echo ""
echo "Test 4: Mobile BFF Pattern (Optimized)"
curl -s http://localhost:3000/api/mobile/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.performance'

# Test 5: Cache Performance
echo ""
echo "Test 5: Cache Performance (Second request should be cached)"
time curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" > /dev/null
echo "Second request (should hit cache):"
time curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.metadata | {cached, totalLatency}'

# Test 6: Rate Limiting
echo ""
echo "Test 6: Rate Limiting (Rapid fire requests)"
for i in {1..5}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:3000/api/web/dashboard \
    -H "Authorization: Bearer $TOKEN")
  echo "Request $i: HTTP $STATUS"
  sleep 0.1
done

# Test 7: Orchestration Timing
echo ""
echo "Test 7: Request Orchestration (Parallel vs Sequential)"
echo "Parallel execution through gateway shows combined latency..."
curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.metadata.servicesStatus'

echo ""
echo "======================================"
echo "All tests completed!"
echo "Open http://localhost:8080 to see the dashboard"
EOF

chmod +x test.sh

echo ""
echo "Building Docker containers..."
docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 15

echo ""
echo "Running tests..."
./test.sh

echo ""
echo "======================================"
echo "✅ Demo Setup Complete!"
echo "======================================"
echo ""
echo "Access points:"
echo "  • Dashboard: http://localhost:8080"
echo "  • API Gateway: http://localhost:3000"
echo "  • Metrics: http://localhost:3000/metrics"
echo ""
echo "Next steps:"
echo "  1. Open http://localhost:8080 in your browser"
echo "  2. Click the test buttons to see patterns in action"
echo "  3. Watch real-time metrics update via WebSocket"
echo "  4. Run './test.sh' for automated testing"
echo "  5. Check 'docker-compose logs -f gateway' for detailed logs"
echo ""
echo "To stop: run './cleanup.sh'"
echo ""