import express from 'express';
import cors from 'cors';
import axios from 'axios';

const app = express();
app.use(cors());
app.use(express.json());

const orders = [];
let requestCount = 0;
let errorCount = 0;

// Service-per-subdomain: Order service coordinates but doesn't own inventory/payment data
app.post('/api/orders', async (req, res) => {
  const startTime = Date.now();
  requestCount++;
  
  try {
    const { productId, quantity } = req.body;
    
    // Network call to inventory service (milliseconds, can fail)
    let inventoryCheck;
    try {
      const inventoryResponse = await axios.post('http://inventory-service:3004/api/inventory/check', 
        { productId, quantity },
        { timeout: 2000 }
      );
      inventoryCheck = inventoryResponse.data;
    } catch (error) {
      errorCount++;
      return res.status(503).json({ 
        error: 'Inventory service unavailable', 
        architecture: 'microservices' 
      });
    }
    
    if (!inventoryCheck.available) {
      errorCount++;
      return res.status(400).json({ error: 'Insufficient inventory' });
    }
    
    // Create order
    const order = {
      id: `ORD-${Date.now()}`,
      productId,
      quantity,
      total: inventoryCheck.price * quantity,
      status: 'pending',
      createdAt: new Date().toISOString()
    };
    orders.push(order);
    
    // Network call to payment service (milliseconds, can fail)
    let payment;
    try {
      const paymentResponse = await axios.post('http://payment-service:3003/api/payments', 
        { orderId: order.id, amount: order.total },
        { timeout: 2000 }
      );
      payment = paymentResponse.data;
    } catch (error) {
      errorCount++;
      order.status = 'payment-failed';
      return res.status(503).json({ 
        error: 'Payment service unavailable', 
        order,
        architecture: 'microservices' 
      });
    }
    
    // Network call to reserve inventory (milliseconds, can fail)
    try {
      await axios.post('http://inventory-service:3004/api/inventory/reserve', 
        { productId, quantity },
        { timeout: 2000 }
      );
    } catch (error) {
      errorCount++;
      return res.status(503).json({ 
        error: 'Failed to reserve inventory', 
        architecture: 'microservices' 
      });
    }
    
    order.status = 'completed';
    
    const latency = Date.now() - startTime;
    res.json({ 
      order, 
      payment,
      architecture: 'microservices',
      latency: `${latency}ms`,
      hops: 3
    });
  } catch (error) {
    errorCount++;
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/orders/metrics', (req, res) => {
  res.json({
    service: 'order',
    requests: requestCount,
    errors: errorCount,
    errorRate: requestCount > 0 ? ((errorCount / requestCount) * 100).toFixed(2) + '%' : '0%',
    orders: orders.length
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'order' }));

const PORT = 3002;
app.listen(PORT, () => console.log(`Order Service running on port ${PORT}`));
