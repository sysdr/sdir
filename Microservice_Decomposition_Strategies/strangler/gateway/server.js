import express from 'express';
import cors from 'cors';
import axios from 'axios';

const app = express();
app.use(cors());
app.use(express.json());

// Feature flags for gradual migration
const featureFlags = {
  useNewPaymentService: 0.5, // 50% traffic to new service
  useNewInventoryService: 0.0  // 0% traffic (not migrated yet)
};

let totalRequests = 0;
let newServiceRequests = 0;
let legacyRequests = 0;

app.post('/api/strangler/order', async (req, res) => {
  const startTime = Date.now();
  totalRequests++;
  
  try {
    const { productId, quantity } = req.body;
    
    // Decision: Route payment to new service or legacy monolith
    const useNewPayment = Math.random() < featureFlags.useNewPaymentService;
    
    if (useNewPayment) {
      // Strangler pattern: New service handles payment
      newServiceRequests++;
      
      // Call legacy for inventory (not yet migrated)
      const inventoryResponse = await axios.post('http://legacy-monolith:3006/api/inventory/check',
        { productId, quantity },
        { timeout: 2000 }
      );
      
      if (!inventoryResponse.data.available) {
        return res.status(400).json({ error: 'Insufficient inventory' });
      }
      
      const order = {
        id: `ORD-${Date.now()}`,
        productId,
        quantity,
        total: inventoryResponse.data.price * quantity,
        status: 'pending'
      };
      
      // NEW: Call new payment service
      const paymentResponse = await axios.post('http://new-payment-service:3007/api/payments',
        { orderId: order.id, amount: order.total },
        { timeout: 2000 }
      );
      
      // Call legacy to reserve inventory
      await axios.post('http://legacy-monolith:3006/api/inventory/reserve',
        { productId, quantity },
        { timeout: 2000 }
      );
      
      order.status = 'completed';
      const latency = Date.now() - startTime;
      
      res.json({
        order,
        payment: paymentResponse.data,
        architecture: 'strangler',
        route: 'new-payment',
        latency: `${latency}ms`,
        migrationProgress: '50%'
      });
    } else {
      // Route to legacy monolith
      legacyRequests++;
      
      const response = await axios.post('http://legacy-monolith:3006/api/order',
        { productId, quantity },
        { timeout: 2000 }
      );
      
      const latency = Date.now() - startTime;
      
      res.json({
        ...response.data,
        architecture: 'strangler',
        route: 'legacy',
        latency: `${latency}ms`,
        migrationProgress: '50%'
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/strangler/metrics', (req, res) => {
  res.json({
    architecture: 'strangler',
    totalRequests,
    newServiceRequests,
    legacyRequests,
    migrationProgress: {
      payment: `${featureFlags.useNewPaymentService * 100}%`,
      inventory: `${featureFlags.useNewInventoryService * 100}%`
    },
    trafficSplit: {
      new: ((newServiceRequests / totalRequests) * 100).toFixed(1) + '%',
      legacy: ((legacyRequests / totalRequests) * 100).toFixed(1) + '%'
    }
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'strangler-gateway' }));

const PORT = 3005;
app.listen(PORT, () => console.log(`Strangler Gateway running on port ${PORT}`));
