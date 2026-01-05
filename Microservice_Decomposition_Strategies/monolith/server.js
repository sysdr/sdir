import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

// In-memory data stores
const inventory = {
  'PROD-001': { id: 'PROD-001', name: 'Laptop', stock: 50, price: 999.99 },
  'PROD-002': { id: 'PROD-002', name: 'Mouse', stock: 200, price: 29.99 },
  'PROD-003': { id: 'PROD-003', name: 'Keyboard', stock: 150, price: 79.99 }
};

const orders = [];
const payments = [];

let requestCount = 0;
let errorCount = 0;

// Monolithic endpoints - all capabilities in one service
app.post('/api/monolith/order', async (req, res) => {
  const startTime = Date.now();
  requestCount++;
  
  try {
    const { productId, quantity } = req.body;
    
    // Check inventory (internal function call - microseconds)
    if (!inventory[productId] || inventory[productId].stock < quantity) {
      errorCount++;
      return res.status(400).json({ error: 'Insufficient inventory' });
    }
    
    // Create order (internal function call)
    const order = {
      id: `ORD-${Date.now()}`,
      productId,
      quantity,
      total: inventory[productId].price * quantity,
      status: 'pending',
      createdAt: new Date().toISOString()
    };
    orders.push(order);
    
    // Process payment (internal function call)
    const payment = {
      id: `PAY-${Date.now()}`,
      orderId: order.id,
      amount: order.total,
      status: 'completed',
      processedAt: new Date().toISOString()
    };
    payments.push(payment);
    
    // Update inventory (internal function call)
    inventory[productId].stock -= quantity;
    
    order.status = 'completed';
    
    const latency = Date.now() - startTime;
    res.json({ 
      order, 
      payment, 
      architecture: 'monolith',
      latency: `${latency}ms`,
      hops: 0 
    });
  } catch (error) {
    errorCount++;
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/monolith/metrics', (req, res) => {
  res.json({
    architecture: 'monolith',
    requests: requestCount,
    errors: errorCount,
    errorRate: requestCount > 0 ? ((errorCount / requestCount) * 100).toFixed(2) + '%' : '0%',
    orders: orders.length,
    avgLatency: '2-5ms'
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3001;
app.listen(PORT, () => console.log(`Monolith running on port ${PORT}`));
