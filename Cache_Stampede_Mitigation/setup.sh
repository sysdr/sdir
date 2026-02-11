#!/bin/bash

set -e

echo "🚀 Setting up Thundering Herd Demo..."

# Create directory structure
mkdir -p thundering-herd/{backend,frontend,load-generator,tests}

# ============================================================================
# BACKEND SERVICE (Express + Redis + PostgreSQL)
# ============================================================================

cat > thundering-herd/backend/package.json << 'EOF'
{
  "name": "cache-stampede-backend",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.12",
    "pg": "^8.11.3",
    "cors": "^2.8.5",
    "ws": "^8.16.0"
  }
}
EOF

cat > thundering-herd/backend/server.js << 'EOF'
import express from 'express';
import cors from 'cors';
import { createClient } from 'redis';
import pg from 'pg';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// Metrics tracking
const metrics = {
  cacheHits: 0,
  cacheMisses: 0,
  dbQueries: 0,
  coalesced: 0,
  activeDbConnections: 0,
  requestLatencies: [],
  stampedes: 0
};

// Redis setup
const redis = createClient({ url: 'redis://redis:6379' });
await redis.connect();

// PostgreSQL setup
const { Pool } = pg;
const pool = new Pool({
  host: 'postgres',
  user: 'demo',
  password: 'demo',
  database: 'stampede_demo',
  max: 20 // Limited connection pool to show stampede effects
});

// In-flight request tracking for coalescing
const inflightRequests = new Map();

// Broadcast metrics to all connected clients
function broadcastMetrics() {
  const payload = JSON.stringify({
    type: 'metrics',
    data: {
      ...metrics,
      avgLatency: metrics.requestLatencies.length > 0 
        ? Math.round(metrics.requestLatencies.reduce((a, b) => a + b, 0) / metrics.requestLatencies.length)
        : 0
    }
  });
  
  wss.clients.forEach(client => {
    if (client.readyState === 1) client.send(payload);
  });
}

setInterval(broadcastMetrics, 100);

// Simulate expensive database query
async function expensiveDbQuery(productId) {
  const start = Date.now();
  metrics.activeDbConnections++;
  metrics.dbQueries++;
  
  try {
    // Simulate complex query with joins and aggregations
    await new Promise(resolve => setTimeout(resolve, 100 + Math.random() * 50));
    
    const result = await pool.query(
      'SELECT * FROM products WHERE id = $1',
      [productId]
    );
    
    const latency = Date.now() - start;
    metrics.requestLatencies.push(latency);
    if (metrics.requestLatencies.length > 100) metrics.requestLatencies.shift();
    
    return result.rows[0] || { id: productId, name: `Product ${productId}`, price: 99.99 };
  } finally {
    metrics.activeDbConnections--;
  }
}

// Strategy 1: No Mitigation (causes stampede)
app.get('/api/product/:id/no-mitigation', asyncHandler(async (req, res) => {
  const productId = req.params.id;
  const cacheKey = `product:${productId}`;
  
  // Check cache
  const cached = await redis.get(cacheKey);
  if (cached) {
    metrics.cacheHits++;
    return res.json({ data: JSON.parse(cached), cached: true, strategy: 'none' });
  }
  
  metrics.cacheMisses++;
  
  // Cache miss - everyone hits database
  const data = await expensiveDbQuery(productId);
  await redis.setEx(cacheKey, 5, JSON.stringify(data)); // 5 second TTL
  
  res.json({ data, cached: false, strategy: 'none' });
}));

// Strategy 2: Request Coalescing
app.get('/api/product/:id/coalescing', asyncHandler(async (req, res) => {
  const productId = req.params.id;
  const cacheKey = `product:${productId}:coalesced`;
  
  // Check cache
  const cached = await redis.get(cacheKey);
  if (cached) {
    metrics.cacheHits++;
    return res.json({ data: JSON.parse(cached), cached: true, strategy: 'coalescing' });
  }
  
  metrics.cacheMisses++;
  
  // Check if request is already in-flight
  if (inflightRequests.has(cacheKey)) {
    metrics.coalesced++;
    const data = await inflightRequests.get(cacheKey);
    return   res.json({ data, cached: false, coalesced: true, strategy: 'coalescing' });
  }

  // Create promise for this request
  const fetchPromise = expensiveDbQuery(productId).then(async (data) => {
    await redis.setEx(cacheKey, 5, JSON.stringify(data));
    inflightRequests.delete(cacheKey);
    return data;
  });
  
  inflightRequests.set(cacheKey, fetchPromise);
  const data = await fetchPromise;
  
  res.json({ data, cached: false, strategy: 'coalescing' });
}));

// Strategy 3: Probabilistic Early Expiration
app.get('/api/product/:id/probabilistic', asyncHandler(async (req, res) => {
  const productId = req.params.id;
  const cacheKey = `product:${productId}:prob`;
  const ttl = 10; // 10 seconds base TTL
  const beta = 1.0;
  
  const cached = await redis.get(cacheKey);
  const cacheAge = await redis.ttl(cacheKey);
  
  // Calculate probability of early refresh
  if (cached && cacheAge > 0) {
    const timeRemaining = cacheAge;
    const delta = ttl * beta * Math.log(Math.random());
    
    // Refresh early if delta suggests it
    if (timeRemaining < Math.abs(delta)) {
      // Refresh in background, serve stale data
      expensiveDbQuery(productId).then(async (data) => {
        await redis.setEx(cacheKey, ttl, JSON.stringify(data));
      });
      metrics.cacheHits++;
      return res.json({ 
        data: JSON.parse(cached), 
        cached: true, 
        refreshed: true,
        strategy: 'probabilistic' 
      });
    }
    
    metrics.cacheHits++;
    return res.json({ data: JSON.parse(cached), cached: true, strategy: 'probabilistic' });
  }
  
  metrics.cacheMisses++;
  const data = await expensiveDbQuery(productId);
  await redis.setEx(cacheKey, ttl, JSON.stringify(data));
  
  res.json({ data, cached: false, strategy: 'probabilistic' });
}));

// Strategy 4: Stale-While-Revalidate
app.get('/api/product/:id/stale-revalidate', asyncHandler(async (req, res) => {
  const productId = req.params.id;
  const cacheKey = `product:${productId}:swr`;
  const staleKey = `${cacheKey}:stale`;
  
  const cached = await redis.get(cacheKey);
  if (cached) {
    metrics.cacheHits++;
    return res.json({ data: JSON.parse(cached), cached: true, strategy: 'stale-revalidate' });
  }
  
  // Check stale data
  const stale = await redis.get(staleKey);
  if (stale) {
    // Serve stale, revalidate in background
    expensiveDbQuery(productId).then(async (data) => {
      await redis.setEx(cacheKey, 5, JSON.stringify(data));
      await redis.setEx(staleKey, 30, JSON.stringify(data)); // Stale for 30s
    });
    
    metrics.cacheHits++;
    return res.json({ 
      data: JSON.parse(stale), 
      cached: true, 
      stale: true,
      strategy: 'stale-revalidate' 
    });
  }
  
  metrics.cacheMisses++;
  const data = await expensiveDbQuery(productId);
  await redis.setEx(cacheKey, 5, JSON.stringify(data));
  await redis.setEx(staleKey, 30, JSON.stringify(data));
  
  res.json({ data, cached: false, strategy: 'stale-revalidate' });
}));

// Strategy 5: Jittered TTL
app.get('/api/product/:id/jittered', asyncHandler(async (req, res) => {
  const productId = req.params.id;
  const cacheKey = `product:${productId}:jitter`;
  
  const cached = await redis.get(cacheKey);
  if (cached) {
    metrics.cacheHits++;
    return res.json({ data: JSON.parse(cached), cached: true, strategy: 'jittered' });
  }
  
  metrics.cacheMisses++;
  const data = await expensiveDbQuery(productId);
  
  // Add 20% jitter to TTL
  const baseTTL = 5;
  const jitter = Math.random() * baseTTL * 0.2;
  const finalTTL = Math.floor(baseTTL + jitter);
  
  await redis.setEx(cacheKey, finalTTL, JSON.stringify(data));
  
  res.json({ data, cached: false, ttl: finalTTL, strategy: 'jittered' });
}));

// Metrics endpoint
app.get('/api/metrics', (req, res) => {
  res.json(metrics);
});

// Reset metrics
app.post('/api/reset', asyncHandler(async (req, res) => {
  metrics.cacheHits = 0;
  metrics.cacheMisses = 0;
  metrics.dbQueries = 0;
  metrics.coalesced = 0;
  metrics.activeDbConnections = 0;
  metrics.requestLatencies = [];
  metrics.stampedes = 0;

  try {
    await redis.flushAll();
  } catch (e) {
    console.warn('Redis flushAll failed:', e.message);
  }

  res.json({ success: true });
}));

// 404 for favicon and other unknown routes (avoids browser 404 noise)
app.get('/favicon.ico', (req, res) => res.status(204).end());

// Error handling middleware (must be last)
app.use((err, req, res, next) => {
  console.error('Request error:', err.message || err);
  res.status(500).json({ error: 'Internal Server Error', message: err.message || 'Something went wrong' });
});

const PORT = 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend running on port ${PORT}`);
});
EOF

cat > thundering-herd/backend/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# ============================================================================
# FRONTEND DASHBOARD
# ============================================================================

cat > thundering-herd/frontend/package.json << 'EOF'
{
  "name": "cache-stampede-frontend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "recharts": "^2.10.3"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.0.12"
  }
}
EOF

cat > thundering-herd/frontend/vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { host: '0.0.0.0', port: 3000 }
});
EOF

cat > thundering-herd/frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cache Stampede Mitigation Demo</title>
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ctext y='24' font-size='24'%3E⚡%3C/text%3E%3C/svg%3E">
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

mkdir -p thundering-herd/frontend/src

cat > thundering-herd/frontend/src/main.jsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './style.css';

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
EOF

cat > thundering-herd/frontend/src/style.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: linear-gradient(135deg, #e3f2fd 0%, #f5f5f5 100%);
  min-height: 100vh;
  padding: 20px;
}

.app {
  max-width: 1600px;
  margin: 0 auto;
}

.header {
  text-align: center;
  margin-bottom: 30px;
}

.header h1 {
  color: #1565c0;
  font-size: 32px;
  margin-bottom: 8px;
  text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
}

.header p {
  color: #546e7a;
  font-size: 16px;
}

.controls {
  display: flex;
  gap: 15px;
  margin-bottom: 25px;
  justify-content: center;
  flex-wrap: wrap;
}

.btn {
  padding: 12px 24px;
  border: none;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

.btn-primary {
  background: linear-gradient(135deg, #1e88e5 0%, #1565c0 100%);
  color: white;
}

.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 12px rgba(30, 136, 229, 0.3);
}

.btn-danger {
  background: linear-gradient(135deg, #e53935 0%, #c62828 100%);
  color: white;
}

.btn-secondary {
  background: white;
  color: #1565c0;
  border: 2px solid #1565c0;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 15px;
  margin-bottom: 25px;
}

.metric-card {
  background: white;
  padding: 20px;
  border-radius: 12px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.08);
  border-left: 4px solid #1e88e5;
}

.metric-label {
  color: #78909c;
  font-size: 13px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 8px;
}

.metric-value {
  color: #1565c0;
  font-size: 28px;
  font-weight: 700;
}

.metric-subtext {
  color: #90a4ae;
  font-size: 12px;
  margin-top: 4px;
}

.strategy-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 20px;
  margin-bottom: 25px;
}

.strategy-card {
  background: white;
  padding: 20px;
  border-radius: 12px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.08);
  transition: transform 0.3s ease;
}

.strategy-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 20px rgba(0,0,0,0.12);
}

.strategy-card h3 {
  color: #1565c0;
  font-size: 18px;
  margin-bottom: 12px;
  display: flex;
  align-items: center;
  gap: 8px;
}

.status-indicator {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #66bb6a;
  box-shadow: 0 0 8px rgba(102, 187, 106, 0.6);
  animation: pulse 2s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.strategy-stats {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
  margin-top: 15px;
}

.stat-item {
  background: #f5f5f5;
  padding: 10px;
  border-radius: 6px;
}

.stat-label {
  color: #78909c;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
}

.stat-value {
  color: #424242;
  font-size: 20px;
  font-weight: 700;
  margin-top: 4px;
}

.alert {
  background: #fff3e0;
  border-left: 4px solid #ff9800;
  padding: 15px 20px;
  border-radius: 8px;
  margin-bottom: 20px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}

.alert-danger {
  background: #ffebee;
  border-left-color: #e53935;
}

.alert strong {
  color: #e65100;
}
EOF

cat > thundering-herd/frontend/src/App.jsx << 'EOF'
import React, { useState, useEffect } from 'react';

const STRATEGIES = [
  { id: 'no-mitigation', name: 'No Mitigation', color: '#e53935' },
  { id: 'coalescing', name: 'Request Coalescing', color: '#43a047' },
  { id: 'probabilistic', name: 'Probabilistic Early Expiration', color: '#1e88e5' },
  { id: 'stale-revalidate', name: 'Stale-While-Revalidate', color: '#fb8c00' },
  { id: 'jittered', name: 'Jittered TTL', color: '#8e24aa' }
];

export default function App() {
  const [metrics, setMetrics] = useState({
    cacheHits: 0,
    cacheMisses: 0,
    dbQueries: 0,
    coalesced: 0,
    activeDbConnections: 0,
    avgLatency: 0,
    stampedes: 0
  });
  
  const [loading, setLoading] = useState(false);
  const [stampede, setStampede] = useState(false);

  useEffect(() => {
    const ws = new WebSocket('ws://localhost:3001');
    
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === 'metrics') {
        setMetrics(message.data);
      }
    };
    
    return () => ws.close();
  }, []);

  const triggerLoad = async (strategy, concurrent = 100) => {
    setLoading(true);
    setStampede(strategy === 'no-mitigation');
    
    const requests = [];
    for (let i = 0; i < concurrent; i++) {
      requests.push(
        fetch(`http://localhost:3001/api/product/1/${strategy}`)
          .then(r => r.json())
      );
    }
    
    await Promise.all(requests);
    setLoading(false);
    setTimeout(() => setStampede(false), 2000);
  };

  const reset = async () => {
    await fetch('http://localhost:3001/api/reset', { method: 'POST' });
  };

  const hitRate = metrics.cacheHits + metrics.cacheMisses > 0
    ? ((metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses)) * 100).toFixed(1)
    : 0;

  return (
    <div className="app">
      <div className="header">
        <h1>⚡ Cache Stampede Mitigation Dashboard</h1>
        <p>Real-time demonstration of thundering herd prevention strategies</p>
      </div>

      {stampede && (
        <div className="alert alert-danger">
          <strong>⚠️ STAMPEDE DETECTED!</strong> Database connections spiking. This is what happens without mitigation.
        </div>
      )}

      <div className="controls">
        {STRATEGIES.map(strategy => (
          <button
            key={strategy.id}
            className="btn btn-primary"
            onClick={() => triggerLoad(strategy.id, 100)}
            disabled={loading}
          >
            Test {strategy.name}
          </button>
        ))}
        <button className="btn btn-danger" onClick={reset}>
          Reset Metrics
        </button>
      </div>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-label">Cache Hit Rate</div>
          <div className="metric-value">{hitRate}%</div>
          <div className="metric-subtext">
            {metrics.cacheHits} hits / {metrics.cacheMisses} misses
          </div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">DB Queries</div>
          <div className="metric-value">{metrics.dbQueries}</div>
          <div className="metric-subtext">
            {metrics.coalesced} coalesced requests
          </div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Active DB Connections</div>
          <div className="metric-value">{metrics.activeDbConnections}</div>
          <div className="metric-subtext">Pool size: 20 connections</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Avg Latency</div>
          <div className="metric-value">{metrics.avgLatency}ms</div>
          <div className="metric-subtext">Last 100 requests</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Stampedes</div>
          <div className="metric-value">{metrics.stampedes ?? 0}</div>
          <div className="metric-subtext">Concurrent stampede events</div>
        </div>
      </div>

      <div className="strategy-grid">
        {STRATEGIES.map(strategy => (
          <div key={strategy.id} className="strategy-card">
            <h3>
              <span className="status-indicator" />
              {strategy.name}
            </h3>
            <p style={{ color: '#546e7a', fontSize: '14px', marginTop: '8px' }}>
              {getStrategyDescription(strategy.id)}
            </p>
            <div className="strategy-stats">
              <div className="stat-item">
                <div className="stat-label">Effectiveness</div>
                <div className="stat-value">{getEffectiveness(strategy.id)}</div>
              </div>
              <div className="stat-item">
                <div className="stat-label">Complexity</div>
                <div className="stat-value">{getComplexity(strategy.id)}</div>
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="alert">
        <strong>💡 Tip:</strong> Watch the "Active DB Connections" metric. No mitigation causes 100 concurrent DB queries. 
        Coalescing reduces it to 1. Stale-while-revalidate keeps serving users even during refresh.
      </div>
    </div>
  );
}

function getStrategyDescription(id) {
  const descriptions = {
    'no-mitigation': 'Every cache miss triggers a DB query. Causes stampedes.',
    'coalescing': 'Concurrent requests wait for first query to complete.',
    'probabilistic': 'Randomly refresh before expiration based on TTL.',
    'stale-revalidate': 'Serve stale data while refreshing in background.',
    'jittered': 'Add random variance to TTL to prevent synchronized expiration.'
  };
  return descriptions[id];
}

function getEffectiveness(id) {
  const ratings = {
    'no-mitigation': '❌',
    'coalescing': '⭐⭐⭐⭐',
    'probabilistic': '⭐⭐⭐',
    'stale-revalidate': '⭐⭐⭐⭐⭐',
    'jittered': '⭐⭐⭐'
  };
  return ratings[id];
}

function getComplexity(id) {
  const complexity = {
    'no-mitigation': 'Low',
    'coalescing': 'Medium',
    'probabilistic': 'Medium',
    'stale-revalidate': 'High',
    'jittered': 'Low'
  };
  return complexity[id];
}
EOF

cat > thundering-herd/frontend/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
EOF

# ============================================================================
# DATABASE INITIALIZATION
# ============================================================================

cat > thundering-herd/init.sql << 'EOF'
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (id, name, price, description) VALUES
(1, 'Premium Widget', 99.99, 'High-traffic product that commonly causes cache stampedes'),
(2, 'Standard Widget', 49.99, 'Medium-traffic product'),
(3, 'Basic Widget', 19.99, 'Low-traffic product');
EOF

# ============================================================================
# DOCKER COMPOSE
# ============================================================================

cat > thundering-herd/docker-compose.yml << 'EOF'
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: stampede_demo
      POSTGRES_USER: demo
      POSTGRES_PASSWORD: demo
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U demo"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  backend:
    build: ./backend
    ports:
      - "3001:3001"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      NODE_ENV: production

  frontend:
    build: ./frontend
    ports:
      - "3000:3000"
    depends_on:
      - backend

volumes:
  postgres_data:
EOF

# ============================================================================
# TESTS
# ============================================================================

cat > thundering-herd/tests/test-stampede.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Cache Stampede Tests..."

BASE_URL="http://localhost:3001"

# Reset metrics
curl -s -X POST "$BASE_URL/api/reset" > /dev/null

echo ""
echo "Test 1: No Mitigation (Should cause stampede)"
echo "Sending 50 concurrent requests..."

# Send concurrent requests
for i in {1..50}; do
  curl -s "$BASE_URL/api/product/1/no-mitigation" > /dev/null &
done
wait

sleep 1
METRICS=$(curl -s "$BASE_URL/api/metrics")
DB_QUERIES=$(echo $METRICS | grep -o '"dbQueries":[0-9]*' | grep -o '[0-9]*')

echo "DB Queries: $DB_QUERIES"
if [ "$DB_QUERIES" -gt 40 ]; then
  echo "✅ PASS: Stampede occurred ($DB_QUERIES queries for 50 requests)"
else
  echo "❌ FAIL: Expected >40 queries, got $DB_QUERIES"
fi

echo ""
echo "Test 2: Request Coalescing (Should prevent stampede)"
curl -s -X POST "$BASE_URL/api/reset" > /dev/null

for i in {1..50}; do
  curl -s "$BASE_URL/api/product/1/coalescing" > /dev/null &
done
wait

sleep 1
METRICS=$(curl -s "$BASE_URL/api/metrics")
DB_QUERIES=$(echo $METRICS | grep -o '"dbQueries":[0-9]*' | grep -o '[0-9]*')
COALESCED=$(echo $METRICS | grep -o '"coalesced":[0-9]*' | grep -o '[0-9]*')

echo "DB Queries: $DB_QUERIES, Coalesced: $COALESCED"
if [ "$DB_QUERIES" -lt 5 ] && [ "$COALESCED" -gt 40 ]; then
  echo "✅ PASS: Coalescing prevented stampede ($COALESCED requests coalesced)"
else
  echo "❌ FAIL: Expected <5 queries and >40 coalesced"
fi

echo ""
echo "Test 3: Stale-While-Revalidate"
curl -s -X POST "$BASE_URL/api/reset" > /dev/null

# Prime cache
curl -s "$BASE_URL/api/product/1/stale-revalidate" > /dev/null
sleep 6  # Wait for cache to expire

# This should serve stale data
RESPONSE=$(curl -s "$BASE_URL/api/product/1/stale-revalidate")
IS_STALE=$(echo $RESPONSE | grep -o '"stale":true')

if [ ! -z "$IS_STALE" ]; then
  echo "✅ PASS: Served stale data while revalidating"
else
  echo "❌ FAIL: Did not serve stale data"
fi

echo ""
echo "All tests completed!"
EOF

chmod +x thundering-herd/tests/test-stampede.sh

# ============================================================================
# BUILD AND RUN
# ============================================================================

cd thundering-herd

echo ""
echo "📦 Building Docker containers..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 10

echo ""
echo "✅ Demo ready!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔧 API: http://localhost:3001"
echo ""
echo "From project root: ./demo.sh (tests), ./cleanup.sh (when done)"
echo ""
echo "📝 Try testing each strategy from the dashboard!"