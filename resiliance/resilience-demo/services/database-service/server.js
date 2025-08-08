const express = require('express');
const prometheus = require('prom-client');
const winston = require('winston');
const cors = require('cors');

const app = express();
const PORT = 3002;

app.use(cors());
app.use(express.json());

// Metrics setup
const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

const dbQueryDuration = new prometheus.Histogram({
  name: 'db_query_duration_seconds',
  help: 'Duration of database queries in seconds',
  labelNames: ['operation'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 3, 5]
});

register.registerMetric(dbQueryDuration);

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

// Chaos variables
let chaosConfig = {
  latencyMs: 0,
  errorRate: 0,
  cpuIntensive: false,
  memoryLeak: false
};

// Simulate database with in-memory store
const database = {
  '1': { id: '1', name: 'Alice Johnson', email: 'alice@example.com', role: 'admin' },
  '2': { id: '2', name: 'Bob Smith', email: 'bob@example.com', role: 'user' },
  '3': { id: '3', name: 'Carol Davis', email: 'carol@example.com', role: 'user' },
  '4': { id: '4', name: 'David Wilson', email: 'david@example.com', role: 'moderator' },
  '5': { id: '5', name: 'Eve Brown', email: 'eve@example.com', role: 'user' }
};

// Chaos injection middleware
function applyChaos(req, res, next) {
  // Simulate errors
  if (Math.random() < chaosConfig.errorRate) {
    logger.warn('Chaos-induced error', { endpoint: req.path });
    return res.status(500).json({ error: 'Database connection failed' });
  }
  
  // Simulate CPU spike
  if (chaosConfig.cpuIntensive) {
    const start = Date.now();
    while (Date.now() - start < 100) {
      Math.random() * Math.random();
    }
  }
  
  // Simulate memory leak
  if (chaosConfig.memoryLeak) {
    global.memoryLeak = global.memoryLeak || [];
    global.memoryLeak.push(new Array(1000000).fill('leak'));
  }
  
  // Simulate network latency
  setTimeout(next, chaosConfig.latencyMs);
}

app.use(applyChaos);

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'database-service', 
    status: 'healthy',
    chaos: chaosConfig,
    memoryUsage: process.memoryUsage()
  });
});

// Get user from database
app.get('/db/user/:id', (req, res) => {
  const start = Date.now();
  const userId = req.params.id;
  
  logger.info(`Database query for user ${userId}`);
  
  // Simulate database query delay
  setTimeout(() => {
    const user = database[userId];
    const duration = (Date.now() - start) / 1000;
    
    dbQueryDuration.observe({ operation: 'select' }, duration);
    
    if (user) {
      res.json({
        ...user,
        source: 'database',
        queryTime: duration,
        timestamp: new Date().toISOString()
      });
    } else {
      res.status(404).json({ error: 'User not found', userId });
    }
  }, 50 + Math.random() * 100); // Simulate realistic DB latency
});

// Chaos control endpoints
app.post('/chaos/latency', (req, res) => {
  chaosConfig.latencyMs = req.body.latencyMs || 0;
  logger.info(`Latency chaos set to ${chaosConfig.latencyMs}ms`);
  res.json({ message: 'Latency chaos applied', latencyMs: chaosConfig.latencyMs });
});

app.post('/chaos/errors', (req, res) => {
  chaosConfig.errorRate = req.body.errorRate || 0;
  logger.info(`Error rate chaos set to ${chaosConfig.errorRate}`);
  res.json({ message: 'Error chaos applied', errorRate: chaosConfig.errorRate });
});

app.post('/chaos/cpu', (req, res) => {
  chaosConfig.cpuIntensive = req.body.enabled || false;
  logger.info(`CPU chaos set to ${chaosConfig.cpuIntensive}`);
  res.json({ message: 'CPU chaos applied', enabled: chaosConfig.cpuIntensive });
});

app.post('/chaos/memory', (req, res) => {
  chaosConfig.memoryLeak = req.body.enabled || false;
  if (!chaosConfig.memoryLeak && global.memoryLeak) {
    global.memoryLeak = null;
    if (global.gc) global.gc();
  }
  logger.info(`Memory chaos set to ${chaosConfig.memoryLeak}`);
  res.json({ message: 'Memory chaos applied', enabled: chaosConfig.memoryLeak });
});

app.get('/chaos/status', (req, res) => {
  res.json(chaosConfig);
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.listen(PORT, () => {
  logger.info(`Database service listening on port ${PORT}`);
});
