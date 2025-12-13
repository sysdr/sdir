const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3002;
const INVENTORY_SERVICE_URL = process.env.INVENTORY_SERVICE_URL || 'http://inventory-service:3003';

let requestCount = 0;
let activeRequests = 0;
const MAX_THREADS = 10;

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
    console.log(`[${timestamp}] Order Service - Request ${reqId} started (Active: ${activeRequests}/${MAX_THREADS})`);
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
    service: 'order-service',
    status: 'healthy',
    activeRequests,
    maxThreads: MAX_THREADS,
    utilization: `${Math.round((activeRequests / MAX_THREADS) * 100)}%`,
    requestCount
  });
});

app.get('/orders/user/:userId', async (req, res) => {
  const userId = req.params.userId;
  
  if (activeRequests >= MAX_THREADS) {
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Thread pool exhausted'
    });
  }
  
  try {
    const seenIds = req.headers['x-seen-request-ids'] || '';
    const newSeenIds = seenIds ? `${seenIds},${req.requestId}` : req.requestId;
    
    // Add delay to make activeRequests visible in dashboard
    // Dashboard polls every 200ms, so we need at least 300ms delay
    // to ensure requests are visible during processing
    await new Promise(resolve => setTimeout(resolve, 300));
    
    const response = await axios.get(`${INVENTORY_SERVICE_URL}/inventory/check`, {
      headers: {
        'x-request-id': req.requestId,
        'x-seen-request-ids': newSeenIds
      },
      params: { userId },
      timeout: 5000
    });
    
    res.json({
      orderId: `ORD-${Date.now()}`,
      userId,
      items: response.data,
      status: 'confirmed',
      requestId: req.requestId
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to check inventory',
      message: error.message,
      requestId: req.requestId
    });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    service: 'order-service',
    totalRequests: requestCount,
    activeRequests,
    maxThreads: MAX_THREADS,
    threadUtilization: Math.round((activeRequests / MAX_THREADS) * 100)
  });
});

app.post('/reset-stats', (req, res) => {
  requestCount = 0;
  console.log('🔄 Statistics reset for Order Service');
  res.json({
    service: 'order-service',
    message: 'Statistics reset successfully',
    totalRequests: requestCount,
    activeRequests
  });
});

app.listen(PORT, () => {
  console.log(`✅ Order Service running on port ${PORT}`);
});
