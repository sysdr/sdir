const express = require('express');
const client = require('prom-client');

const app = express();
const PORT = 3003;

// Prometheus metrics
const register = new client.Registry();
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

let artificialDelay = 0;
let requestCount = 0;
let errorCount = 0;

app.use(express.json());

// Middleware to track metrics
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
  });
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'service-c', delay: artificialDelay });
});

// Main data endpoint
app.get('/data', async (req, res) => {
  requestCount++;
  
  // Simulate processing with artificial delay
  if (artificialDelay > 0) {
    await new Promise(resolve => setTimeout(resolve, artificialDelay));
  } else {
    // Normal operation: 50-100ms
    await new Promise(resolve => setTimeout(resolve, Math.random() * 50 + 50));
  }
  
  res.json({ 
    data: 'Database query result',
    service: 'service-c',
    timestamp: new Date().toISOString(),
    processingTime: artificialDelay || 'normal'
  });
});

// Control endpoint to inject delay
app.post('/control/delay', (req, res) => {
  const { delay } = req.body;
  artificialDelay = delay;
  console.log(`🐌 Artificial delay set to ${delay}ms`);
  res.json({ message: `Delay set to ${delay}ms`, currentDelay: artificialDelay });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  const metrics = await register.metrics();
  res.send(metrics);
});

// Status endpoint
app.get('/status', (req, res) => {
  res.json({
    service: 'service-c',
    requestCount,
    errorCount,
    artificialDelay,
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(`✅ Service C (Database) running on port ${PORT}`);
  console.log(`   Normal latency: 50-100ms`);
});
