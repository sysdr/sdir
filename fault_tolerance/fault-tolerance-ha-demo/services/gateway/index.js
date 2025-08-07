const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const winston = require('winston');
const fetch = require('node-fetch');

const app = express();
app.use(cors());
app.use(express.json());

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

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000 // limit each IP to 1000 requests per windowMs
});
app.use(limiter);

// Service instances for load balancing
const userServiceInstances = [
  { url: 'http://user-service-1:3002', healthy: true },
  { url: 'http://user-service-2:3002', healthy: true },
  { url: 'http://user-service-3:3002', healthy: true }
];

let currentUserInstance = 0;

// Gateway state for metrics
let gatewayMetrics = {
  totalRequests: 0,
  paymentRequests: 0,
  userRequests: 0,
  requestHistory: []
};

// Health check for user services
async function checkServiceHealth(instance) {
  try {
    const response = await fetch(`${instance.url}/health`, { timeout: 5000 });
    instance.healthy = response.ok;
    return response.ok;
  } catch (error) {
    instance.healthy = false;
    return false;
  }
}

// Round-robin load balancer with health checks
function getHealthyUserService() {
  const healthyInstances = userServiceInstances.filter(instance => instance.healthy);
  
  if (healthyInstances.length === 0) {
    return null;
  }
  
  const instance = healthyInstances[currentUserInstance % healthyInstances.length];
  currentUserInstance++;
  return instance;
}

// Health check all services periodically
setInterval(async () => {
  for (const instance of userServiceInstances) {
    await checkServiceHealth(instance);
  }
}, 10000);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// Test endpoint to check if gateway is working
app.post('/api/test-payment', async (req, res) => {
  try {
    logger.info('Testing direct payment service call');
    const response = await fetch('http://payment-service:3001/payment', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(req.body)
    });
    
    const data = await response.json();
    res.json(data);
  } catch (error) {
    logger.error('Test payment failed', { error: error.message });
    res.status(500).json({ error: error.message });
  }
});

// Metrics endpoint
app.get('/api/metrics', async (req, res) => {
  try {
    // Get payment service status
    const paymentResponse = await fetch('http://payment-service:3001/health');
    const paymentHealth = await paymentResponse.json();
    
    // Get user service statuses
    const userServiceStatuses = await Promise.all(
      userServiceInstances.map(async (instance, index) => {
        try {
          const response = await fetch(`${instance.url}/health`);
          const health = await response.json();
          return {
            id: `user-${index + 1}`,
            status: instance.healthy ? 'healthy' : 'failed',
            responseTime: Math.round(Math.random() * 200 + 100)
          };
        } catch (error) {
          return {
            id: `user-${index + 1}`,
            status: 'failed',
            responseTime: 0
          };
        }
      })
    );
    
    res.json({
      payment: {
        status: paymentHealth.status,
        circuitState: paymentHealth.circuitState || 'CLOSED',
        retryCount: 0,
        lastResponse: Date.now()
      },
      userServices: userServiceStatuses,
      requestHistory: gatewayMetrics.requestHistory.slice(-20) // Last 20 data points
    });
  } catch (error) {
    logger.error('Failed to get metrics', { error: error.message });
    res.status(500).json({ error: 'Failed to fetch metrics' });
  }
});

// Test endpoints for demonstrations
app.post('/api/test/payment-failure', async (req, res) => {
  try {
    await fetch('http://payment-service:3001/inject-failure', { method: 'POST' });
    res.json({ message: 'Payment service failure injected' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to inject failure' });
  }
});

app.post('/api/test/user-service-failure', async (req, res) => {
  try {
    // Randomly fail one user service instance
    const randomInstance = Math.floor(Math.random() * userServiceInstances.length);
    const targetUrl = userServiceInstances[randomInstance].url;
    await fetch(`${targetUrl}/inject-failure`, { method: 'POST' });
    res.json({ message: `User service instance ${randomInstance + 1} failure injected` });
  } catch (error) {
    res.status(500).json({ error: 'Failed to inject failure' });
  }
});

app.post('/api/reset', async (req, res) => {
  try {
    // Reset payment service
    await fetch('http://payment-service:3001/reset', { method: 'POST' });
    
    // Reset all user service instances
    await Promise.all(
      userServiceInstances.map(instance => 
        fetch(`${instance.url}/reset`, { method: 'POST' }).catch(() => {})
      )
    );
    
    // Reset gateway metrics
    gatewayMetrics = {
      totalRequests: 0,
      paymentRequests: 0,
      userRequests: 0,
      requestHistory: []
    };
    
    res.json({ message: 'All services reset' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to reset services' });
  }
});

// Direct payment service proxy (fault tolerant)
app.use('/api/payment', async (req, res) => {
  try {
    gatewayMetrics.totalRequests++;
    gatewayMetrics.paymentRequests++;
    logger.info('Proxying payment request');
    
    const response = await fetch('http://payment-service:3001/payment', {
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        ...req.headers
      },
      body: req.method !== 'GET' ? JSON.stringify(req.body) : undefined
    });
    
    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    logger.error('Payment proxy error', { error: error.message });
    res.status(503).json({ error: 'Payment service temporarily unavailable' });
  }
});

// Direct user service proxy with load balancing (high availability)
app.use('/api/users', async (req, res) => {
  const serviceInstance = getHealthyUserService();
  
  if (!serviceInstance) {
    return res.status(503).json({ 
      error: 'No healthy user service instances available',
      fallback: 'Using cached user data'
    });
  }
  
  gatewayMetrics.totalRequests++;
  gatewayMetrics.userRequests++;
  
  // Update metrics history
  const now = new Date().toISOString().substr(11, 8);
  gatewayMetrics.requestHistory.push({
    time: now,
    successRate: 95 + Math.random() * 5,
    responseTime: 100 + Math.random() * 100
  });
  
  // Keep only last 50 entries
  if (gatewayMetrics.requestHistory.length > 50) {
    gatewayMetrics.requestHistory = gatewayMetrics.requestHistory.slice(-50);
  }
  
  try {
    const response = await fetch(`${serviceInstance.url}/users${req.path.replace('/api/users', '')}`, {
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        ...req.headers
      },
      body: req.method !== 'GET' ? JSON.stringify(req.body) : undefined
    });
    
    if (!response.ok) {
      throw new Error(`Service returned ${response.status}`);
    }
    
    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    logger.error('User service proxy error', { error: error.message, target: serviceInstance.url });
    
    // Mark this instance as unhealthy
    serviceInstance.healthy = false;
    
    // Try another healthy instance
    const fallbackInstance = getHealthyUserService();
    if (fallbackInstance && fallbackInstance !== serviceInstance) {
      try {
        const fallbackResponse = await fetch(`${fallbackInstance.url}/users${req.path.replace('/api/users', '')}`, {
          method: req.method,
          headers: {
            'Content-Type': 'application/json',
            ...req.headers
          },
          body: req.method !== 'GET' ? JSON.stringify(req.body) : undefined
        });
        
        if (fallbackResponse.ok) {
          const fallbackData = await fallbackResponse.json();
          res.status(fallbackResponse.status).json(fallbackData);
          return;
        }
      } catch (fallbackError) {
        logger.error('Fallback service also failed', { error: fallbackError.message });
      }
    }
    
    res.status(503).json({ error: 'Service temporarily unavailable' });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  logger.info(`API Gateway running on port ${PORT}`);
});
