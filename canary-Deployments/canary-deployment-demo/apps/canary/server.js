const express = require('express');
const cors = require('cors');
const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

let requestCount = 0;
let errorCount = 0;
const startTime = Date.now();

// Simulate some performance issues in canary (configurable)
const SIMULATE_ISSUES = process.env.SIMULATE_ISSUES === 'true';
const ERROR_RATE = parseFloat(process.env.ERROR_RATE || '0.05'); // 5% default

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    version: '2.0.0',
    uptime: Date.now() - startTime,
    requests: requestCount,
    errors: errorCount
  });
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.json({
    version: '2.0.0',
    requests: requestCount,
    errors: errorCount,
    errorRate: requestCount > 0 ? (errorCount / requestCount) * 100 : 0,
    uptime: Date.now() - startTime
  });
});

// Main application endpoint
app.get('/', (req, res) => {
  requestCount++;
  
  // Simulate errors if configured
  if (SIMULATE_ISSUES && Math.random() < ERROR_RATE) {
    errorCount++;
    return res.status(500).json({
      error: 'Internal server error in canary version',
      version: '2.0.0'
    });
  }
  
  const latency = SIMULATE_ISSUES ? 
    Math.random() * 200 + 50 : // 50-250ms when issues enabled
    Math.random() * 40 + 8;    // 8-48ms when stable
  
  setTimeout(() => {
    res.json({
      version: '2.0.0 (Canary)',
      message: 'Welcome to our enhanced e-commerce platform',
      features: ['Advanced checkout', 'AI recommendations', 'Social features', 'Product catalog', 'User accounts'],
      latency: Math.round(latency),
      timestamp: new Date().toISOString(),
      server: 'canary-v2'
    });
  }, latency);
});

// Enhanced product listing endpoint
app.get('/products', (req, res) => {
  requestCount++;
  res.json({
    version: '2.0.0',
    products: [
      { id: 1, name: 'Laptop', price: 999, recommendation: 'Popular choice!' },
      { id: 2, name: 'Phone', price: 599, recommendation: 'Latest model' },
      { id: 3, name: 'Tablet', price: 399, recommendation: 'Great for reading' },
      { id: 4, name: 'Smartwatch', price: 299, recommendation: 'New arrival!' }
    ]
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Canary app v2.0.0 running on port ${PORT}`);
});
