const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const Redis = require('redis');
const CircuitBreaker = require('opossum');
const cors = require('cors');
const promClient = require('prom-client');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: { origin: "*", methods: ["GET", "POST"] }
});

app.use(cors());
app.use(express.json());

// Redis client
const redis = Redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
redis.connect().catch(console.error);

// Prometheus metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [1, 5, 15, 50, 100, 500]
});
register.registerMetric(httpRequestDuration);

// Circuit breaker for database operations
const dbOptions = {
  timeout: 3000,
  errorThresholdPercentage: 50,
  resetTimeout: 30000,
  rollingCountTimeout: 10000,
  rollingCountBuckets: 10
};

const dbCircuitBreaker = new CircuitBreaker(dbOperation, dbOptions);

// System metrics
let systemMetrics = {
  currentRPS: 0,
  activeConnections: 0,
  circuitBreakerState: 'CLOSED',
  avgResponseTime: 0,
  errorRate: 0,
  scalingEvents: [],
  requestCount: 0,
  errorCount: 0
};

let loadTestActive = false;
let requestTimes = [];

// Middleware to track requests
app.use((req, res, next) => {
  const start = Date.now();
  systemMetrics.activeConnections++;
  systemMetrics.requestCount++;

  res.on('finish', () => {
    const duration = Date.now() - start;
    requestTimes.push(duration);
    
    // Keep only last 100 response times
    if (requestTimes.length > 100) {
      requestTimes = requestTimes.slice(-100);
    }
    
    systemMetrics.avgResponseTime = requestTimes.reduce((a, b) => a + b, 0) / requestTimes.length;
    systemMetrics.activeConnections--;
    
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
    
    if (res.statusCode >= 400) {
      systemMetrics.errorCount++;
    }
  });

  next();
});

// Simulate database operation
async function dbOperation(query) {
  // Simulate varying response times under load
  const baseDelay = loadTestActive ? Math.random() * 100 + 50 : Math.random() * 20 + 10;
  const loadMultiplier = systemMetrics.currentRPS > 1000 ? 1.5 : 1;
  const delay = baseDelay * loadMultiplier;
  
  await new Promise(resolve => setTimeout(resolve, delay));
  
  // Simulate occasional failures under high load
  if (loadTestActive && systemMetrics.currentRPS > 2000 && Math.random() < 0.1) {
    throw new Error('Database overloaded');
  }
  
  return { data: `Result for ${query}`, timestamp: new Date().toISOString() };
}

// Circuit breaker event handlers
dbCircuitBreaker.on('open', () => {
  systemMetrics.circuitBreakerState = 'OPEN';
  addScalingEvent('Circuit breaker OPENED - High error rate detected', 'scale-down');
});

dbCircuitBreaker.on('halfOpen', () => {
  systemMetrics.circuitBreakerState = 'HALF_OPEN';
  addScalingEvent('Circuit breaker HALF-OPEN - Testing recovery', 'scale-up');
});

dbCircuitBreaker.on('close', () => {
  systemMetrics.circuitBreakerState = 'CLOSED';
  addScalingEvent('Circuit breaker CLOSED - Normal operation resumed', 'scale-up');
});

function addScalingEvent(description, type) {
  systemMetrics.scalingEvents.push({
    timestamp: new Date().toLocaleTimeString(),
    description,
    type
  });
  
  // Keep only last 50 events
  if (systemMetrics.scalingEvents.length > 50) {
    systemMetrics.scalingEvents = systemMetrics.scalingEvents.slice(-50);
  }
}

// API Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/api/products', async (req, res) => {
  try {
    if (systemMetrics.circuitBreakerState === 'OPEN') {
      // Serve cached response when circuit breaker is open
      return res.json({
        products: ['Cached Product 1', 'Cached Product 2'],
        cached: true,
        message: 'Serving cached data due to high error rate'
      });
    }

    const result = await dbCircuitBreaker.fire('SELECT * FROM products');
    res.json({ products: result.data, cached: false });
  } catch (error) {
    res.status(500).json({ 
      error: 'Service temporarily unavailable',
      circuitBreaker: systemMetrics.circuitBreakerState
    });
  }
});

app.post('/api/load-test/start', (req, res) => {
  loadTestActive = true;
  addScalingEvent('Black Friday load test started', 'scale-up');
  res.json({ message: 'Load test started', active: true });
});

app.post('/api/load-test/stop', (req, res) => {
  loadTestActive = false;
  addScalingEvent('Load test stopped - Scaling down', 'scale-down');
  res.json({ message: 'Load test stopped', active: false });
});

app.get('/metrics', (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});

// Calculate and broadcast metrics every second
setInterval(() => {
  // Calculate RPS (requests per second)
  const currentTime = Date.now();
  const timeWindow = 1000; // 1 second
  systemMetrics.currentRPS = Math.floor(Math.random() * (loadTestActive ? 3000 : 100));
  
  // Calculate error rate
  systemMetrics.errorRate = systemMetrics.requestCount > 0 
    ? (systemMetrics.errorCount / systemMetrics.requestCount) * 100 
    : 0;

  // Auto-scaling simulation based on RPS
  if (systemMetrics.currentRPS > 2000 && Math.random() < 0.1) {
    addScalingEvent(`High load detected: ${systemMetrics.currentRPS} RPS - Scaling up`, 'scale-up');
  } else if (systemMetrics.currentRPS < 100 && Math.random() < 0.05) {
    addScalingEvent(`Low load detected: ${systemMetrics.currentRPS} RPS - Scaling down`, 'scale-down');
  }

  // Broadcast metrics to connected clients
  io.emit('metrics', systemMetrics);
}, 1000);

// WebSocket connection handling
io.on('connection', (socket) => {
  console.log('Client connected');
  socket.emit('metrics', systemMetrics);
  
  socket.on('disconnect', () => {
    console.log('Client disconnected');
  });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`🚀 Black Friday API running on port ${PORT}`);
  console.log(`📊 Metrics endpoint: http://localhost:${PORT}/metrics`);
});
