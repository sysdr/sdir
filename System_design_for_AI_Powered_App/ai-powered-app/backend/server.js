const express = require('express');
const cors = require('cors');
const redis = require('redis');
const { Pool } = require('pg');
const axios = require('axios');
const WebSocket = require('ws');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(cors());
app.use(express.json());

// Redis client
const redisClient = redis.createClient({ url: process.env.REDIS_URL });
redisClient.connect().catch(console.error);

// PostgreSQL client
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Initialize database
(async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS requests (
      id SERIAL PRIMARY KEY,
      query_text TEXT,
      model_used VARCHAR(20),
      latency_ms FLOAT,
      cached BOOLEAN,
      cost_units FLOAT,
      created_at TIMESTAMP DEFAULT NOW()
    )
  `);
  
  await pool.query(`
    CREATE TABLE IF NOT EXISTS metrics (
      id SERIAL PRIMARY KEY,
      metric_name VARCHAR(50),
      metric_value FLOAT,
      timestamp TIMESTAMP DEFAULT NOW()
    )
  `);
})();

// Metrics tracking
const metrics = {
  totalRequests: 0,
  cacheHits: 0,
  fastModelCalls: 0,
  heavyModelCalls: 0,
  totalLatency: 0,
  totalCost: 0
};

// Cost calculation (per 1000 tokens)
const COSTS = {
  fast: 0.0001,   // $0.0001 per request
  heavy: 0.001    // $0.001 per request
};

// Broadcast metrics to all connected clients
function broadcastMetrics() {
  const stats = {
    ...metrics,
    avgLatency: metrics.totalRequests > 0 ? metrics.totalLatency / metrics.totalRequests : 0,
    cacheHitRate: metrics.totalRequests > 0 ? (metrics.cacheHits / metrics.totalRequests * 100).toFixed(1) : 0,
    costPerRequest: metrics.totalRequests > 0 ? (metrics.totalCost / metrics.totalRequests).toFixed(6) : 0
  };
  
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({ type: 'metrics', data: stats }));
    }
  });
}

// WebSocket connection
wss.on('connection', (ws) => {
  console.log('Client connected to metrics stream');
  broadcastMetrics();
});

setInterval(broadcastMetrics, 1000);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.post('/api/query', async (req, res) => {
  const { text, model } = req.body;
  const startTime = Date.now();
  
  try {
    // Call model service
    const response = await axios.post(`${process.env.MODEL_SERVICE_URL}/embed`, {
      text,
      model
    });
    
    const latency = Date.now() - startTime;
    const cached = response.data.cached;
    const modelUsed = response.data.model;
    const cost = COSTS[modelUsed];
    
    // Update metrics
    metrics.totalRequests++;
    if (cached) metrics.cacheHits++;
    if (modelUsed === 'fast') metrics.fastModelCalls++;
    if (modelUsed === 'heavy') metrics.heavyModelCalls++;
    metrics.totalLatency += latency;
    metrics.totalCost += cost;
    
    // Store in database
    await pool.query(
      'INSERT INTO requests (query_text, model_used, latency_ms, cached, cost_units) VALUES ($1, $2, $3, $4, $5)',
      [text, modelUsed, latency, cached, cost]
    );
    
    broadcastMetrics();
    
    res.json({
      embedding: response.data.embedding,
      cached,
      model: modelUsed,
      latency_ms: latency,
      cost_usd: cost,
      routed_by: response.data.routed_by
    });
  } catch (error) {
    console.error('Query error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/similarity', async (req, res) => {
  const { text1, text2, model } = req.body;
  const startTime = Date.now();
  
  try {
    const response = await axios.post(`${process.env.MODEL_SERVICE_URL}/similarity`, {
      text1,
      text2,
      model: model || 'fast'
    });
    
    const latency = Date.now() - startTime;
    const cost = COSTS[response.data.model] * 2; // Two embeddings
    const cached = response.data.text1_cached || response.data.text2_cached;
    
    metrics.totalRequests++;
    if (response.data.text1_cached) metrics.cacheHits++;
    if (response.data.text2_cached) metrics.cacheHits++;
    if (response.data.model === 'fast') metrics.fastModelCalls += 2;
    if (response.data.model === 'heavy') metrics.heavyModelCalls += 2;
    metrics.totalLatency += latency;
    metrics.totalCost += cost;
    
    // Store in database for history & latency charts
    const queryText = [text1, text2].map(t => (t || '').substring(0, 50)).join(' | ');
    await pool.query(
      'INSERT INTO requests (query_text, model_used, latency_ms, cached, cost_units) VALUES ($1, $2, $3, $4, $5)',
      [queryText, response.data.model, latency, cached, cost]
    );
    
    broadcastMetrics();
    
    res.json({
      ...response.data,
      cost_usd: cost
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/metrics', (req, res) => {
  res.json({
    ...metrics,
    avgLatency: metrics.totalRequests > 0 ? metrics.totalLatency / metrics.totalRequests : 0,
    cacheHitRate: metrics.totalRequests > 0 ? (metrics.cacheHits / metrics.totalRequests * 100) : 0
  });
});

app.get('/api/history', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM requests ORDER BY created_at DESC LIMIT 100'
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

server.listen(5000, () => {
  console.log('Backend running on port 5000');
});
