const express = require('express');
const axios = require('axios');
const client = require('prom-client');

const app = express();
const PORT = 3002;

// Prometheus metrics
const register = new client.Registry();
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

let requestCount = 0;
let errorCount = 0;
let timeoutCount = 0;
let activeRequests = 0;
const MAX_CONCURRENT = 50;

app.use(express.json());

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
  });
  next();
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'service-b',
    activeRequests,
    maxConcurrent: MAX_CONCURRENT
  });
});

// Business logic endpoint that calls Service C
app.get('/process', async (req, res) => {
  requestCount++;
  activeRequests++;
  
  // Check if we're overloaded
  if (activeRequests > MAX_CONCURRENT) {
    activeRequests--;
    return res.status(503).json({ error: 'Service overloaded', activeRequests });
  }
  
  try {
    const start = Date.now();
    
    // Call Service C with 2 second timeout
    const response = await axios.get('http://service-c:3003/data', {
      timeout: 2000
    });
    
    const duration = Date.now() - start;
    
    // Add some business logic processing
    await new Promise(resolve => setTimeout(resolve, 50));
    
    activeRequests--;
    res.json({
      result: 'Business logic processed',
      service: 'service-b',
      downstreamData: response.data,
      processingTime: duration,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    activeRequests--;
    errorCount++;
    
    if (error.code === 'ECONNABORTED') {
      timeoutCount++;
      console.log(`⏱️ Timeout calling Service C (${timeoutCount} total timeouts)`);
      return res.status(504).json({ 
        error: 'Timeout calling downstream service',
        message: 'Service C is too slow',
        timeoutCount
      });
    }
    
    console.error('Error calling Service C:', error.message);
    res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.send(metrics);
});

app.get('/status', (req, res) => {
  res.json({
    service: 'service-b',
    requestCount,
    errorCount,
    timeoutCount,
    activeRequests,
    maxConcurrent: MAX_CONCURRENT,
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(`✅ Service B (Business Logic) running on port ${PORT}`);
  console.log(`   Timeout for Service C calls: 2 seconds`);
  console.log(`   Max concurrent requests: ${MAX_CONCURRENT}`);
});
