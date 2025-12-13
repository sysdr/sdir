const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3003;
const USER_SERVICE_URL = process.env.USER_SERVICE_URL || 'http://user-service:3001';

let requestCount = 0;
let activeRequests = 0;
const MAX_THREADS = 10;
let circularCallsEnabled = true;

app.use((req, res, next) => {
  requestCount++;
  
  // Don't count health/stats endpoints in activeRequests to avoid inflating
  // the count with monitoring/health check requests
  const isMonitoringEndpoint = req.path === '/health' || req.path === '/stats';
  
  const reqId = req.headers['x-request-id'] || `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  req.requestId = reqId;
  
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
    console.log(`[${timestamp}] Inventory Service - Request ${reqId} started (Active: ${activeRequests}/${MAX_THREADS})`);
  }
  
  // Ensure activeRequests is decremented when response finishes
  res.on('finish', () => {
    if (!isMonitoringEndpoint) {
      activeRequests = Math.max(0, activeRequests - 1); // Prevent negative values
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
    service: 'inventory-service',
    status: 'healthy',
    activeRequests,
    maxThreads: MAX_THREADS,
    utilization: `${Math.round((activeRequests / MAX_THREADS) * 100)}%`,
    requestCount,
    circularCallsEnabled
  });
});

app.post('/toggle-circular', (req, res) => {
  circularCallsEnabled = !circularCallsEnabled;
  console.log(`🔄 Circular calls ${circularCallsEnabled ? 'ENABLED' : 'DISABLED'}`);
  res.json({ circularCallsEnabled });
});

app.get('/inventory/check', async (req, res) => {
  const userId = req.query.userId;
  
  if (activeRequests >= MAX_THREADS) {
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Thread pool exhausted'
    });
  }
  
  // Add delay to make activeRequests visible in dashboard
  // Dashboard polls every 200ms, so we need at least 300ms delay
  // to ensure requests are visible during processing
  await new Promise(resolve => setTimeout(resolve, 300));
  
  // This creates the circular dependency!
  if (circularCallsEnabled && userId) {
    try {
      const seenIds = req.headers['x-seen-request-ids'] || '';
      const newSeenIds = seenIds ? `${seenIds},${req.requestId}` : req.requestId;
      
      console.log(`⚠️  CIRCULAR CALL: Inventory calling User Service for userId=${userId}`);
      
      const response = await axios.get(`${USER_SERVICE_URL}/user/${userId}`, {
        headers: {
          'x-request-id': req.requestId,
          'x-seen-request-ids': newSeenIds
        },
        timeout: 5000
      });
      
      res.json({
        available: true,
        stock: 42,
        userVerified: response.data,
        requestId: req.requestId
      });
    } catch (error) {
      if (error.response?.status === 508) {
        console.log(`🛑 Circular dependency prevented for request ${req.requestId}`);
        return res.status(200).json({
          available: true,
          stock: 42,
          userVerified: false,
          message: 'Circular call prevented by circuit breaker',
          requestId: req.requestId
        });
      }
      
      res.status(500).json({
        error: 'Failed to verify user',
        message: error.message,
        requestId: req.requestId
      });
    }
  } else {
    res.json({
      available: true,
      stock: 42,
      requestId: req.requestId
    });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    service: 'inventory-service',
    totalRequests: requestCount,
    activeRequests,
    maxThreads: MAX_THREADS,
    threadUtilization: Math.round((activeRequests / MAX_THREADS) * 100),
    circularCallsEnabled
  });
});

app.post('/reset-stats', (req, res) => {
  requestCount = 0;
  console.log('🔄 Statistics reset for Inventory Service');
  res.json({
    service: 'inventory-service',
    message: 'Statistics reset successfully',
    totalRequests: requestCount,
    activeRequests,
    circularCallsEnabled
  });
});

app.listen(PORT, () => {
  console.log(`✅ Inventory Service running on port ${PORT}`);
});
