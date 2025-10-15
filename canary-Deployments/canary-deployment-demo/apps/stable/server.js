const express = require('express');
const cors = require('cors');
const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

let requestCount = 0;
let errorCount = 0;
const startTime = Date.now();

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    version: '1.0.0',
    uptime: Date.now() - startTime,
    requests: requestCount,
    errors: errorCount
  });
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.json({
    version: '1.0.0',
    requests: requestCount,
    errors: errorCount,
    errorRate: requestCount > 0 ? (errorCount / requestCount) * 100 : 0,
    uptime: Date.now() - startTime
  });
});

// Main application endpoint
app.get('/', (req, res) => {
  requestCount++;
  const latency = Math.random() * 50 + 10; // 10-60ms
  
  setTimeout(() => {
    res.json({
      version: '1.0.0 (Stable)',
      message: 'Welcome to our stable e-commerce platform',
      features: ['Basic checkout', 'Product catalog', 'User accounts'],
      latency: Math.round(latency),
      timestamp: new Date().toISOString(),
      server: 'stable-v1'
    });
  }, latency);
});

// Product listing endpoint
app.get('/products', (req, res) => {
  requestCount++;
  res.json({
    version: '1.0.0',
    products: [
      { id: 1, name: 'Laptop', price: 999 },
      { id: 2, name: 'Phone', price: 599 },
      { id: 3, name: 'Tablet', price: 399 }
    ]
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Stable app v1.0.0 running on port ${PORT}`);
});
