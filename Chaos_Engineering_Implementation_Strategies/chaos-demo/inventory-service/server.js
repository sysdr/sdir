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

const inventory = {
  'ITEM-001': { name: 'Laptop', stock: 50, price: 999.99 },
  'ITEM-002': { name: 'Mouse', stock: 200, price: 29.99 },
  'ITEM-003': { name: 'Keyboard', stock: 150, price: 79.99 },
  'ITEM-004': { name: 'Monitor', stock: 75, price: 299.99 },
  'ITEM-005': { name: 'Headphones', stock: 120, price: 149.99 }
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
    return res.status(503).json({ error: 'Chaos injected error', service: 'inventory' });
  }
  
  const delay = chaosConfig.enabled ? chaosConfig.latency : 0;
  setTimeout(() => next(), delay);
}

app.use(injectChaos);

// Check stock endpoint
app.post('/api/check', (req, res) => {
  const { itemId, quantity } = req.body;
  const startTime = Date.now();
  
  setTimeout(() => {
    const item = inventory[itemId];
    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    metrics.successfulRequests++;
    const latency = Date.now() - startTime;
    metrics.avgLatency = ((metrics.avgLatency * (metrics.successfulRequests - 1)) + latency) / metrics.successfulRequests;
    
    res.json({
      available: item.stock >= quantity,
      item: item.name,
      currentStock: item.stock,
      requestedQuantity: quantity,
      price: item.price
    });
  }, Math.random() * 80 + 20);
});

// Reserve stock endpoint
app.post('/api/reserve', (req, res) => {
  const { itemId, quantity } = req.body;
  const item = inventory[itemId];
  
  if (item && item.stock >= quantity) {
    item.stock -= quantity;
    metrics.successfulRequests++;
    res.json({ success: true, remainingStock: item.stock });
  } else {
    metrics.failedRequests++;
    res.status(400).json({ error: 'Insufficient stock' });
  }
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
    chaosConfig,
    inventoryStatus: inventory
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'inventory' });
});

const PORT = 3002;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`📦 Inventory Service running on port ${PORT}`);
});
