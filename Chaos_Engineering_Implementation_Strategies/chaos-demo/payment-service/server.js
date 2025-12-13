const express = require('express');
const app = express();
app.use(express.json());

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

let chaosConfig = {
  errorRate: 0,
  latency: 0,
  enabled: false
};

let metrics = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  avgLatency: 0
};

// Chaos injection middleware
function injectChaos(req, res, next) {
  // Skip chaos injection for control and monitoring endpoints
  if (req.path.startsWith('/chaos/') || req.path === '/health' || req.path === '/metrics') {
    return next();
  }
  
  metrics.totalRequests++;
  
  if (chaosConfig.enabled && Math.random() < chaosConfig.errorRate) {
    metrics.failedRequests++;
    return res.status(500).json({ error: 'Chaos injected error', service: 'payment' });
  }
  
  const delay = chaosConfig.enabled ? chaosConfig.latency : 0;
  setTimeout(() => next(), delay);
}

app.use(injectChaos);

// Payment processing endpoint
app.post('/api/process', (req, res) => {
  const { amount, orderId } = req.body;
  
  const startTime = Date.now();
  const processingTime = Math.random() * 100 + 50;
  
  setTimeout(() => {
    const transactionId = `TXN-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    metrics.successfulRequests++;
    const latency = Date.now() - startTime;
    metrics.avgLatency = ((metrics.avgLatency * (metrics.successfulRequests - 1)) + latency) / metrics.successfulRequests;
    
    res.json({
      success: true,
      transactionId,
      amount,
      orderId,
      processingTime: latency
    });
  }, processingTime);
});

// Chaos control endpoint
app.post('/chaos/config', (req, res) => {
  chaosConfig = { ...chaosConfig, ...req.body };
  console.log('Chaos config updated:', chaosConfig);
  res.json({ success: true, config: chaosConfig });
});

app.get('/chaos/config', (req, res) => {
  res.json(chaosConfig);
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.json({
    ...metrics,
    successRate: metrics.totalRequests > 0 ? (metrics.successfulRequests / metrics.totalRequests * 100).toFixed(2) : 100,
    chaosConfig
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment' });
});

const PORT = 3001;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`💳 Payment Service running on port ${PORT}`);
});
