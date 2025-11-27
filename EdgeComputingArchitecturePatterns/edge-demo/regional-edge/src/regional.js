const express = require('express');
const WebSocket = require('ws');
const Redis = require('ioredis');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3002;
const redis = new Redis({ host: 'redis', port: 6379 });

let metrics = {
  cacheHits: 0,
  cacheMisses: 0,
  aggregated: 0,
  avgLatency: 0
};

// Cache frequently accessed data
async function cacheData(key, data, ttl = 300) {
  await redis.setex(key, ttl, JSON.stringify(data));
}

async function getCachedData(key) {
  const data = await redis.get(key);
  return data ? JSON.parse(data) : null;
}

// Regional aggregation logic
async function aggregateData(data) {
  const start = Date.now();
  
  const cacheKey = `region:${data.region || 'us-west'}`;
  let cached = await getCachedData(cacheKey);
  
  if (cached) {
    metrics.cacheHits++;
  } else {
    metrics.cacheMisses++;
    cached = { devices: [], avgTemp: 0, avgHumidity: 0 };
  }
  
  // Add to regional aggregation
  cached.devices.push(data);
  cached.devices = cached.devices.slice(-100); // Keep last 100
  
  cached.avgTemp = cached.devices.reduce((sum, d) => sum + d.temperature, 0) / cached.devices.length;
  cached.avgHumidity = cached.devices.reduce((sum, d) => sum + d.humidity, 0) / cached.devices.length;
  
  await cacheData(cacheKey, cached);
  
  const latency = Date.now() - start;
  metrics.aggregated++;
  metrics.avgLatency = (metrics.avgLatency + latency) / 2;
  
  return {
    ...data,
    regionalAvg: { temp: cached.avgTemp.toFixed(1), humidity: cached.avgHumidity.toFixed(1) },
    processedAt: 'regional-edge',
    cached: metrics.cacheHits > 0,
    latency
  };
}

app.post('/aggregate', async (req, res) => {
  try {
    const result = await aggregateData(req.body);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  const hitRate = metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses) * 100 || 0;
  res.json({
    tier: 'regional-edge',
    ...metrics,
    cacheHitRate: hitRate.toFixed(1) + '%',
    latencyTarget: '10-50ms'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tier: 'regional-edge' });
});

const server = app.listen(PORT, () => {
  console.log(`Regional Edge running on port ${PORT}`);
  console.log('Caching and aggregating with <50ms latency');
});

// WebSocket for real-time updates
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  console.log('Dashboard connected to Regional Edge');
});
