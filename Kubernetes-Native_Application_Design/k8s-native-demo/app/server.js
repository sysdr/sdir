const express = require('express');
const client = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3000;
const POD_NAME = process.env.POD_NAME || 'unknown';

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

// Structured logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()]
});

// Application state
let isHealthy = false;
let isReady = false;
let requestCount = 0;
let config = {
  maxConcurrent: parseInt(process.env.MAX_CONCURRENT || '100'),
  responseDelay: parseInt(process.env.RESPONSE_DELAY || '10'),
  featureFlag: process.env.FEATURE_FLAG || 'default'
};

// Simulate initialization (database connections, cache warming)
setTimeout(() => {
  isHealthy = true;
  logger.info({ message: 'Application initialized', pod: POD_NAME });
}, 5000);

setTimeout(() => {
  isReady = true;
  logger.info({ message: 'Application ready to serve traffic', pod: POD_NAME });
}, 8000);

// Middleware for request tracking
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
  });
  next();
});

app.use(express.json());

// Liveness probe - checks if app is in unrecoverable state
app.get('/health/live', (req, res) => {
  if (isHealthy) {
    res.status(200).json({ status: 'alive', pod: POD_NAME, timestamp: new Date().toISOString() });
  } else {
    logger.error({ message: 'Liveness check failed', pod: POD_NAME });
    res.status(503).json({ status: 'unhealthy', pod: POD_NAME });
  }
});

// Readiness probe - checks if app can handle traffic
app.get('/health/ready', (req, res) => {
  if (isReady && requestCount < config.maxConcurrent) {
    res.status(200).json({ 
      status: 'ready', 
      pod: POD_NAME, 
      activeRequests: requestCount,
      config: config.featureFlag
    });
  } else {
    res.status(503).json({ 
      status: 'not-ready', 
      pod: POD_NAME, 
      activeRequests: requestCount 
    });
  }
});

// Startup probe - checks if app has finished initialization
app.get('/health/startup', (req, res) => {
  if (isHealthy) {
    res.status(200).json({ status: 'started', pod: POD_NAME });
  } else {
    res.status(503).json({ status: 'starting', pod: POD_NAME });
  }
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Main application endpoint
app.get('/api/process', async (req, res) => {
  requestCount++;
  const requestId = Math.random().toString(36).substring(7);
  const startTime = Date.now();
  
  logger.info({ 
    message: 'Processing request', 
    requestId, 
    pod: POD_NAME,
    activeRequests: requestCount 
  });

  // Simulate processing
  await new Promise(resolve => setTimeout(resolve, config.responseDelay));

  const responseTime = Date.now() - startTime;
  requestCount--;
  
  // Report metrics to aggregator (non-blocking)
  const AGGREGATOR_URL = process.env.AGGREGATOR_URL || 'http://aggregator-service:4000';
  fetch(`${AGGREGATOR_URL}/api/metrics`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ responseTime })
  }).catch(() => {}); // Ignore errors if aggregator is not available
  
  res.json({ 
    requestId, 
    pod: POD_NAME, 
    processed: true,
    featureFlag: config.featureFlag,
    timestamp: new Date().toISOString(),
    responseTime
  });
});

// Status endpoint for dashboard
app.get('/api/status', (req, res) => {
  res.json({
    pod: POD_NAME,
    healthy: isHealthy,
    ready: isReady,
    activeRequests: requestCount,
    config: config,
    uptime: process.uptime(),
    memory: process.memoryUsage()
  });
});

// Simulate random failures for testing
app.post('/api/chaos/crash', (req, res) => {
  logger.error({ message: 'Simulated crash triggered', pod: POD_NAME });
  res.json({ message: 'Crashing in 2 seconds...' });
  setTimeout(() => process.exit(1), 2000);
});

app.post('/api/chaos/unhealthy', (req, res) => {
  isHealthy = false;
  logger.warn({ message: 'Marked as unhealthy', pod: POD_NAME });
  res.json({ message: 'Pod marked unhealthy' });
});

app.post('/api/chaos/notready', (req, res) => {
  isReady = false;
  logger.warn({ message: 'Marked as not ready', pod: POD_NAME });
  res.json({ message: 'Pod marked not ready' });
  setTimeout(() => { isReady = true; }, 30000);
});

// Graceful shutdown handling
let server;
const gracefulShutdown = () => {
  logger.info({ message: 'SIGTERM received, starting graceful shutdown', pod: POD_NAME });
  
  // Stop accepting new connections
  isReady = false;
  
  server.close(() => {
    logger.info({ message: 'Server closed, all connections drained', pod: POD_NAME });
    process.exit(0);
  });

  // Force shutdown after 25 seconds (before K8s SIGKILL at 30s)
  setTimeout(() => {
    logger.error({ message: 'Forced shutdown after timeout', pod: POD_NAME });
    process.exit(1);
  }, 25000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

server = app.listen(PORT, () => {
  logger.info({ message: 'Server starting', port: PORT, pod: POD_NAME });
});
