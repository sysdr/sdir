const express = require('express');
const axios = require('axios');
const redis = require('redis');
const { register, collectDefaultMetrics, Counter, Histogram, Gauge } = require('prom-client');
const CircuitBreaker = require('opossum');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Metrics setup
collectDefaultMetrics();
const requestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code']
});

const circuitBreakerState = new Gauge({
  name: 'circuit_breaker_state',
  help: 'Circuit breaker state (0=closed, 1=open, 2=half-open)',
  labelNames: ['service']
});

const fallbackActivations = new Counter({
  name: 'fallback_activations_total',
  help: 'Total number of fallback activations',
  labelNames: ['service', 'type']
});

// Redis client setup
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://redis:6379'
});

// Circuit breaker configurations
const primaryServiceBreaker = new CircuitBreaker(async () => {}, {
  timeout: 2000,
  errorThresholdPercentage: 50,
  volumeThreshold: 5
});

const recommendationServiceBreaker = new CircuitBreaker(async () => {}, {
  timeout: 1000,
  errorThresholdPercentage: 30,
  volumeThreshold: 3
});

// Mock service states
let serviceStates = {
  primary: { healthy: true, latency: 100 },
  recommendation: { healthy: true, latency: 50 },
  payment: { healthy: true, latency: 200 }
};

app.use(express.json());
app.use(express.static('ui'));

// Middleware for metrics
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    requestDuration.observe(
      { method: req.method, route: req.route?.path || req.path, status_code: res.statusCode },
      duration
    );
  });
  next();
});

// Health endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    services: serviceStates
  });
});

// Graceful degradation endpoint - Product recommendations
app.get('/api/recommendations/:userId', async (req, res) => {
  const { userId } = req.params;
  
  try {
    // Try primary ML-based recommendations
    const recommendationFunction = async () => {
      if (!serviceStates.recommendation.healthy) {
        throw new Error('Recommendation service unhealthy');
      }
      
      await new Promise(resolve => setTimeout(resolve, serviceStates.recommendation.latency));
      
      if (Math.random() < 0.1) { // 10% failure rate for demo
        throw new Error('Random service failure');
      }
      
      return {
        type: 'ml_based',
        items: [
          { id: 1, name: 'AI-Recommended Product 1', score: 0.95 },
          { id: 2, name: 'AI-Recommended Product 2', score: 0.87 },
          { id: 3, name: 'AI-Recommended Product 3', score: 0.76 }
        ]
      };
    };
    
    const recommendationBreaker = new CircuitBreaker(recommendationFunction, {
      timeout: 1000,
      errorThresholdPercentage: 30,
      volumeThreshold: 3
    });
    
    const primaryResult = await recommendationBreaker.fire();
    
    circuitBreakerState.set({ service: 'recommendation' }, 0); // Closed
    res.json({ success: true, data: primaryResult, degraded: false });
    
  } catch (error) {
    // Graceful degradation: Use cached/trending items
    try {
      circuitBreakerState.set({ service: 'recommendation' }, 1); // Open
      fallbackActivations.inc({ service: 'recommendation', type: 'cached' });
      
      // Try Redis cache first (with timeout)
      try {
        const cached = await Promise.race([
          redisClient.get(`trending:${userId}`),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Redis timeout')), 1000))
        ]);
        
        if (cached) {
          res.json({ 
            success: true, 
            data: JSON.parse(cached), 
            degraded: true, 
            fallback: 'cache' 
          });
          return;
        }
      } catch (redisError) {
        // Redis failed, continue to static fallback
        // Redis fallback failed, using static fallback
      }
      
      // Final fallback: Static trending items
      fallbackActivations.inc({ service: 'recommendation', type: 'static' });
      res.json({
        success: true,
        data: {
          type: 'trending',
          items: [
            { id: 101, name: 'Trending Product 1', score: 0.60 },
            { id: 102, name: 'Trending Product 2', score: 0.55 },
            { id: 103, name: 'Trending Product 3', score: 0.50 }
          ]
        },
        degraded: true,
        fallback: 'static'
      });
      
    } catch (fallbackError) {
      res.status(503).json({ 
        success: false, 
        error: 'All recommendation services unavailable',
        degraded: true
      });
    }
  }
});

// Fail-fast endpoint - Payment processing
app.post('/api/payment', async (req, res) => {
  const { amount, currency, cardToken } = req.body;
  
  // Fail-fast validation
  if (!amount || amount <= 0) {
    return res.status(400).json({ 
      success: false, 
      error: 'Invalid amount',
      failFast: true 
    });
  }
  
  if (!currency || !['USD', 'EUR', 'GBP'].includes(currency)) {
    return res.status(400).json({ 
      success: false, 
      error: 'Invalid currency',
      failFast: true 
    });
  }
  
  if (!cardToken) {
    return res.status(400).json({ 
      success: false, 
      error: 'Missing card token',
      failFast: true 
    });
  }
  
  try {
    // Fail fast on payment service health
    if (!serviceStates.payment.healthy) {
      return res.status(503).json({
        success: false,
        error: 'Payment service unavailable - failing fast to prevent data corruption',
        failFast: true
      });
    }
    
    await new Promise(resolve => setTimeout(resolve, serviceStates.payment.latency));
    
    // Simulate payment processing
    if (Math.random() < 0.05) { // 5% failure rate
      return res.status(500).json({
        success: false,
        error: 'Payment processing failed',
        failFast: true
      });
    }
    
    res.json({
      success: true,
      transactionId: `txn_${Date.now()}`,
      amount,
      currency,
      failFast: false
    });
    
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Payment failed - system integrity preserved',
      failFast: true
    });
  }
});

// Admin endpoints to control service states
app.post('/admin/service/:service/toggle', (req, res) => {
  const { service } = req.params;
  if (serviceStates[service]) {
    serviceStates[service].healthy = !serviceStates[service].healthy;
    res.json({ 
      service, 
      healthy: serviceStates[service].healthy,
      message: `${service} service ${serviceStates[service].healthy ? 'enabled' : 'disabled'}`
    });
  } else {
    res.status(404).json({ error: 'Service not found' });
  }
});

app.post('/admin/service/:service/latency', (req, res) => {
  const { service } = req.params;
  const { latency } = req.body;
  
  if (serviceStates[service] && typeof latency === 'number') {
    serviceStates[service].latency = latency;
    res.json({ service, latency, message: `${service} latency set to ${latency}ms` });
  } else {
    res.status(400).json({ error: 'Invalid service or latency value' });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Circuit breaker status
app.get('/circuit-breaker/status', (req, res) => {
  res.json({
    primary: {
      state: primaryServiceBreaker.opened ? 'open' : 'closed',
      failures: primaryServiceBreaker.stats.failures,
      lastFailure: primaryServiceBreaker.stats.lastFailure
    },
    recommendation: {
      state: 'dynamic', // Will be created per request
      failures: 0,
      lastFailure: null
    }
  });
});

// Serve main UI
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../ui/index.html'));
});

// Only start server if this file is run directly
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`🚀 Graceful Degradation Demo running on port ${PORT}`);
    console.log(`📊 Dashboard: http://localhost:${PORT}`);
    console.log(`📈 Metrics: http://localhost:${PORT}/metrics`);
  });
}

module.exports = app;
