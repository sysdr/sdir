const express = require('express');
const axios = require('axios');
const client = require('prom-client');

const app = express();
const PORT = 3001;

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
const MAX_CONCURRENT = 100;

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
    service: 'service-a',
    activeRequests,
    maxConcurrent: MAX_CONCURRENT
  });
});

// API endpoint that calls Service B
app.get('/api/data', async (req, res) => {
  requestCount++;
  activeRequests++;
  
  // Check if we're overloaded
  if (activeRequests > MAX_CONCURRENT) {
    activeRequests--;
    return res.status(503).json({ error: 'API Gateway overloaded', activeRequests });
  }
  
  try {
    const start = Date.now();
    
    // Call Service B with 3 second timeout
    const response = await axios.get('http://service-b:3002/process', {
      timeout: 3000
    });
    
    const duration = Date.now() - start;
    
    // Add some gateway logic
    await new Promise(resolve => setTimeout(resolve, 20));
    
    activeRequests--;
    res.json({
      success: true,
      service: 'service-a',
      data: response.data,
      totalTime: duration,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    activeRequests--;
    errorCount++;
    
    if (error.code === 'ECONNABORTED') {
      timeoutCount++;
      console.log(`⏱️ Timeout calling Service B (${timeoutCount} total timeouts)`);
      return res.status(504).json({ 
        error: 'Gateway timeout',
        message: 'Downstream services are too slow',
        timeoutCount
      });
    }
    
    if (error.response && error.response.status === 504) {
      timeoutCount++;
      console.log(`⏱️ Downstream timeout propagated (${timeoutCount} total)`);
      return res.status(504).json({
        error: 'Cascading timeout',
        message: 'Service B timed out calling Service C',
        timeoutCount
      });
    }
    
    console.error('Error calling Service B:', error.message);
    res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

// Control endpoint to trigger delay in Service C
app.post('/control/slow', async (req, res) => {
  try {
    const { delay } = req.body;
    await axios.post('http://service-c:3003/control/delay', { delay });
    res.json({ message: `Service C delay set to ${delay}ms` });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.send(metrics);
});

app.get('/status', (req, res) => {
  res.json({
    service: 'service-a',
    requestCount,
    errorCount,
    timeoutCount,
    activeRequests,
    maxConcurrent: MAX_CONCURRENT,
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(`✅ Service A (API Gateway) running on port ${PORT}`);
  console.log(`   Timeout for Service B calls: 3 seconds`);
  console.log(`   Max concurrent requests: ${MAX_CONCURRENT}`);
});
