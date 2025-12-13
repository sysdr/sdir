const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3001;
const ORDER_SERVICE_URL = process.env.ORDER_SERVICE_URL || 'http://order-service:3002';

let requestCount = 0;
let activeRequests = 0;
const MAX_THREADS = 10;
let circuitBreakerOpen = false;
const requestHistory = [];

// Middleware to track requests
app.use((req, res, next) => {
  requestCount++;
  
  // Don't count health/stats endpoints in activeRequests to avoid inflating
  // the count with monitoring/health check requests
  const isMonitoringEndpoint = req.path === '/health' || req.path === '/stats';
  
  const reqId = req.headers['x-request-id'] || `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  req.requestId = reqId;
  
  // Check for circular dependency
  const seenIds = req.headers['x-seen-request-ids'] || '';
  if (seenIds.includes(reqId)) {
    console.log(`⛔ CIRCULAR DEPENDENCY DETECTED: ${reqId}`);
    res.status(508).json({
      error: 'Loop Detected',
      requestId: reqId,
      message: 'Circular dependency prevented'
    });
    return;
  }
  
  // Only increment activeRequests for non-monitoring endpoints
  // and ensure we don't exceed MAX_THREADS
  if (!isMonitoringEndpoint) {
    // Prevent counter from going above MAX_THREADS due to race conditions
    if (activeRequests < MAX_THREADS) {
      activeRequests++;
    }
  }
  
  const timestamp = new Date().toISOString();
  if (!isMonitoringEndpoint) {
    console.log(`[${timestamp}] User Service - Request ${reqId} started (Active: ${activeRequests}/${MAX_THREADS})`);
  }
  
  // Ensure activeRequests is decremented when response finishes
  res.on('finish', () => {
    if (!isMonitoringEndpoint) {
      activeRequests = Math.max(0, activeRequests - 1); // Prevent negative values
      console.log(`[${timestamp}] User Service - Request ${reqId} completed (Active: ${activeRequests}/${MAX_THREADS})`);
    }
  });
  
  // Also handle 'close' event in case response is aborted
  res.on('close', () => {
    if (!isMonitoringEndpoint && !res.writableEnded) {
      activeRequests = Math.max(0, activeRequests - 1);
    }
  });
  
  next();
});

app.get('/health', (req, res) => {
  res.json({
    service: 'user-service',
    status: 'healthy',
    activeRequests,
    maxThreads: MAX_THREADS,
    utilization: `${Math.round((activeRequests / MAX_THREADS) * 100)}%`,
    requestCount,
    circuitBreaker: circuitBreakerOpen ? 'OPEN' : 'CLOSED'
  });
});

app.get('/user/:id', async (req, res) => {
  const userId = req.params.id;
  
  res.json({
    userId,
    name: `User ${userId}`,
    email: `user${userId}@example.com`,
    requestId: req.requestId
  });
});

app.get('/user/:id/orders', async (req, res) => {
  const userId = req.params.id;
  
  if (activeRequests >= MAX_THREADS) {
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Thread pool exhausted'
    });
  }
  
  if (circuitBreakerOpen) {
    return res.status(503).json({
      error: 'Circuit Breaker Open',
      message: 'Service temporarily unavailable'
    });
  }
  
  try {
    const seenIds = req.headers['x-seen-request-ids'] || '';
    const newSeenIds = seenIds ? `${seenIds},${req.requestId}` : req.requestId;
    
    const response = await axios.get(`${ORDER_SERVICE_URL}/orders/user/${userId}`, {
      headers: {
        'x-request-id': req.requestId,
        'x-seen-request-ids': newSeenIds
      },
      timeout: 5000
    });
    
    res.json({
      userId,
      orders: response.data,
      requestId: req.requestId
    });
  } catch (error) {
    if (error.code === 'ECONNABORTED') {
      circuitBreakerOpen = true;
      setTimeout(() => { circuitBreakerOpen = false; }, 10000);
    }
    
    res.status(500).json({
      error: 'Failed to fetch orders',
      message: error.message,
      requestId: req.requestId
    });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    service: 'user-service',
    totalRequests: requestCount,
    activeRequests,
    maxThreads: MAX_THREADS,
    threadUtilization: Math.round((activeRequests / MAX_THREADS) * 100),
    circuitBreaker: circuitBreakerOpen ? 'OPEN' : 'CLOSED'
  });
});

app.post('/reset-stats', (req, res) => {
  requestCount = 0;
  requestHistory.length = 0;
  circuitBreakerOpen = false;
  console.log('🔄 Statistics reset for User Service');
  res.json({
    service: 'user-service',
    message: 'Statistics reset successfully',
    totalRequests: requestCount,
    activeRequests,
    circuitBreaker: circuitBreakerOpen ? 'OPEN' : 'CLOSED'
  });
});

app.listen(PORT, () => {
  console.log(`✅ User Service running on port ${PORT}`);
});
