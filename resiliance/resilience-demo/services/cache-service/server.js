const express = require('express');
const prometheus = require('prom-client');
const winston = require('winston');
const cors = require('cors');

const app = express();
const PORT = 3003;

app.use(cors());
app.use(express.json());

// Metrics setup
const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

const cacheHitRate = new prometheus.Counter({
  name: 'cache_hits_total',
  help: 'Total number of cache hits',
  labelNames: ['result']
});

register.registerMetric(cacheHitRate);

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

// In-memory cache with TTL
const cache = new Map();
const TTL = 5 * 60 * 1000; // 5 minutes

// Chaos configuration
let chaosConfig = {
  latencyMs: 0,
  errorRate: 0,
  enabled: false
};

function applyChaos(req, res, next) {
  if (!chaosConfig.enabled) return next();
  
  if (Math.random() < chaosConfig.errorRate) {
    logger.warn('Chaos-induced cache error');
    return res.status(500).json({ error: 'Cache service unavailable' });
  }
  
  setTimeout(next, chaosConfig.latencyMs);
}

app.use(applyChaos);

// Cache cleanup
setInterval(() => {
  const now = Date.now();
  for (const [key, value] of cache.entries()) {
    if (now - value.timestamp > TTL) {
      cache.delete(key);
    }
  }
}, 60000); // Cleanup every minute

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'cache-service', 
    status: 'healthy',
    cacheSize: cache.size,
    chaos: chaosConfig
  });
});

// Get from cache
app.get('/cache/user/:id', (req, res) => {
  const userId = req.params.id;
  const cacheKey = `user:${userId}`;
  
  logger.info(`Cache lookup for user ${userId}`);
  
  const cached = cache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < TTL) {
    cacheHitRate.inc({ result: 'hit' });
    logger.info(`Cache hit for user ${userId}`);
    res.json({
      ...cached.data,
      source: 'cache',
      cachedAt: new Date(cached.timestamp).toISOString()
    });
  } else {
    cacheHitRate.inc({ result: 'miss' });
    logger.info(`Cache miss for user ${userId}`);
    res.status(404).json({ error: 'Not found in cache', userId });
  }
});

// Store in cache
app.post('/cache/user/:id', (req, res) => {
  const userId = req.params.id;
  const cacheKey = `user:${userId}`;
  
  cache.set(cacheKey, {
    data: req.body,
    timestamp: Date.now()
  });
  
  logger.info(`Cached data for user ${userId}`);
  res.json({ message: 'Data cached successfully', userId });
});

// Chaos control
app.post('/chaos/configure', (req, res) => {
  chaosConfig = { ...chaosConfig, ...req.body };
  logger.info('Cache chaos configuration updated', chaosConfig);
  res.json({ message: 'Chaos configuration updated', config: chaosConfig });
});

app.get('/chaos/status', (req, res) => {
  res.json(chaosConfig);
});

// Clear cache
app.delete('/cache/clear', (req, res) => {
  cache.clear();
  logger.info('Cache cleared');
  res.json({ message: 'Cache cleared' });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.listen(PORT, () => {
  logger.info(`Cache service listening on port ${PORT}`);
});
