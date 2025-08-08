const express = require('express');
const axios = require('axios');
const prometheus = require('prom-client');
const winston = require('winston');
const cors = require('cors');
const helmet = require('helmet');

const app = express();
const PORT = 3001;

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Metrics setup
const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

const requestDuration = new prometheus.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});

const requestCounter = new prometheus.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

register.registerMetric(requestDuration);
register.registerMetric(requestCounter);

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

// Circuit breaker state
let circuitBreaker = {
  database: { open: false, failureCount: 0, lastFailure: 0 },
  cache: { open: false, failureCount: 0, lastFailure: 0 }
};

const FAILURE_THRESHOLD = 5;
const RECOVERY_TIMEOUT = 30000; // 30 seconds

function isCircuitOpen(service) {
  const breaker = circuitBreaker[service];
  if (breaker.open && Date.now() - breaker.lastFailure > RECOVERY_TIMEOUT) {
    breaker.open = false;
    breaker.failureCount = 0;
    logger.info(`Circuit breaker for ${service} moved to half-open state`);
  }
  return breaker.open;
}

function recordFailure(service) {
  const breaker = circuitBreaker[service];
  breaker.failureCount++;
  breaker.lastFailure = Date.now();
  
  if (breaker.failureCount >= FAILURE_THRESHOLD) {
    breaker.open = true;
    logger.warn(`Circuit breaker opened for ${service}`);
  }
}

function recordSuccess(service) {
  circuitBreaker[service].failureCount = 0;
}

// Middleware for metrics
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    requestDuration.observe(
      { method: req.method, route: req.route?.path || req.path, status_code: res.statusCode },
      duration
    );
    requestCounter.inc({ method: req.method, route: req.route?.path || req.path, status_code: res.statusCode });
  });
  
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'web-api', 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    circuitBreakers: circuitBreaker 
  });
});

// Main API endpoint with resilience patterns
app.get('/api/users/:id', async (req, res) => {
  const startTime = Date.now();
  const userId = req.params.id;
  
  try {
    logger.info(`Processing request for user ${userId}`);
    
    let userData = null;
    let cacheData = null;
    
    // Try cache first with circuit breaker
    if (!isCircuitOpen('cache')) {
      try {
        const cacheResponse = await axios.get(
          `${process.env.CACHE_SERVICE_URL}/cache/user/${userId}`,
          { timeout: 2000 }
        );
        cacheData = cacheResponse.data;
        recordSuccess('cache');
        logger.info('Cache hit for user', { userId });
      } catch (error) {
        recordFailure('cache');
        logger.warn('Cache service failed', { userId, error: error.message });
      }
    }
    
    // Fetch from database with circuit breaker
    if (!cacheData && !isCircuitOpen('database')) {
      try {
        const dbResponse = await axios.get(
          `${process.env.DATABASE_SERVICE_URL}/db/user/${userId}`,
          { timeout: 5000 }
        );
        userData = dbResponse.data;
        recordSuccess('database');
        
        // Try to update cache (fire and forget)
        if (!isCircuitOpen('cache')) {
          axios.post(`${process.env.CACHE_SERVICE_URL}/cache/user/${userId}`, userData)
            .catch(err => logger.warn('Failed to update cache', { error: err.message }));
        }
      } catch (error) {
        recordFailure('database');
        logger.error('Database service failed', { userId, error: error.message });
        
        // Fallback to default user data
        userData = {
          id: userId,
          name: 'Fallback User',
          email: 'fallback@example.com',
          source: 'fallback'
        };
      }
    }
    
    const responseData = cacheData || userData || {
      id: userId,
      name: 'Default User',
      email: 'default@example.com',
      source: 'default'
    };
    
    responseData.responseTime = Date.now() - startTime;
    responseData.circuitBreakers = Object.keys(circuitBreaker).reduce((acc, key) => {
      acc[key] = circuitBreaker[key].open ? 'open' : 'closed';
      return acc;
    }, {});
    
    res.json(responseData);
    
  } catch (error) {
    logger.error('Unexpected error', { userId, error: error.message });
    res.status(500).json({ 
      error: 'Internal server error', 
      userId,
      responseTime: Date.now() - startTime 
    });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Circuit breaker status
app.get('/circuit-breakers', (req, res) => {
  res.json(circuitBreaker);
});

app.listen(PORT, () => {
  logger.info(`Web API service listening on port ${PORT}`);
});
