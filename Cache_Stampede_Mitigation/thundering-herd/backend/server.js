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
