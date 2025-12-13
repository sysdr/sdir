const express = require('express');
const axios = require('axios');
const app = express();
app.use(express.json());
app.use(express.static('public'));

// Circuit Breaker implementation
class CircuitBreaker {
  constructor(service, threshold = 5, timeout = 10000) {
    this.service = service;
    this.failureThreshold = threshold;
    this.timeout = timeout;
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
  }

  async call(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
        console.log(`Circuit breaker HALF_OPEN for ${this.service}`);
      } else {
        throw new Error(`Circuit breaker OPEN for ${this.service}`);
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  onSuccess() {
    this.failureCount = 0;
    if (this.state === 'HALF_OPEN') {
      this.state = 'CLOSED';
      console.log(`Circuit breaker CLOSED for ${this.service}`);
    }
  }

  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.failureThreshold) {
      this.state = 'OPEN';
      console.log(`Circuit breaker OPEN for ${this.service} (failures: ${this.failureCount})`);
    }
  }

  getState() {
    return {
      service: this.service,
      state: this.state,
      failureCount: this.failureCount,
      lastFailureTime: this.lastFailureTime
    };
  }
}

const paymentBreaker = new CircuitBreaker('payment', 3, 5000);
const inventoryBreaker = new CircuitBreaker('inventory', 3, 5000);

let orderMetrics = {
  totalOrders: 0,
  successfulOrders: 0,
  failedOrders: 0,
  degradedOrders: 0
};

// Retry with exponential backoff
async function retryWithBackoff(fn, maxRetries = 3, baseDelay = 100) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      const delay = baseDelay * Math.pow(2, i);
      console.log(`Retry ${i + 1}/${maxRetries} after ${delay}ms`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

// Order processing with resilience patterns
app.post('/api/order', async (req, res) => {
  const { itemId, quantity, paymentAmount } = req.body;
  orderMetrics.totalOrders++;
  
  const orderId = `ORD-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  let inventoryChecked = false;
  let paymentProcessed = false;
  let degraded = false;

  try {
    // Check inventory with circuit breaker and retry
    try {
      await inventoryBreaker.call(async () => {
        await retryWithBackoff(async () => {
          const response = await axios.post('http://inventory-service:3002/api/check', 
            { itemId, quantity },
            { timeout: 5000 }
          );
          inventoryChecked = response.data.available;
          if (!inventoryChecked) {
            throw new Error('Insufficient stock');
          }
        });
      });
    } catch (error) {
      console.log('Inventory check failed, degrading gracefully');
      degraded = true;
      // Graceful degradation: proceed with order, mark for manual verification
    }

    // Process payment with circuit breaker and retry
    try {
      await paymentBreaker.call(async () => {
        await retryWithBackoff(async () => {
          await axios.post('http://payment-service:3001/api/process',
            { amount: paymentAmount, orderId },
            { timeout: 5000 }
          );
          paymentProcessed = true;
        });
      });
    } catch (error) {
      orderMetrics.failedOrders++;
      return res.status(500).json({
        success: false,
        orderId,
        error: 'Payment processing failed',
        circuitBreakers: {
          payment: paymentBreaker.getState(),
          inventory: inventoryBreaker.getState()
        }
      });
    }

    if (degraded) {
      orderMetrics.degradedOrders++;
    } else {
      orderMetrics.successfulOrders++;
    }

    res.json({
      success: true,
      orderId,
      inventoryChecked,
      paymentProcessed,
      degraded,
      message: degraded ? 'Order accepted with manual verification required' : 'Order processed successfully',
      circuitBreakers: {
        payment: paymentBreaker.getState(),
        inventory: inventoryBreaker.getState()
      }
    });

  } catch (error) {
    orderMetrics.failedOrders++;
    res.status(500).json({
      success: false,
      orderId,
      error: error.message,
      circuitBreakers: {
        payment: paymentBreaker.getState(),
        inventory: inventoryBreaker.getState()
      }
    });
  }
});

// Get system metrics
app.get('/api/metrics', async (req, res) => {
  try {
    const [paymentMetrics, inventoryMetrics] = await Promise.allSettled([
      axios.get('http://payment-service:3001/metrics', { timeout: 2000 }),
      axios.get('http://inventory-service:3002/metrics', { timeout: 2000 })
    ]);

    res.json({
      frontend: {
        ...orderMetrics,
        successRate: orderMetrics.totalOrders > 0 
          ? ((orderMetrics.successfulOrders / orderMetrics.totalOrders) * 100).toFixed(2) 
          : 100,
        circuitBreakers: {
          payment: paymentBreaker.getState(),
          inventory: inventoryBreaker.getState()
        }
      },
      payment: paymentMetrics.status === 'fulfilled' ? paymentMetrics.value.data : { error: 'unavailable' },
      inventory: inventoryMetrics.status === 'fulfilled' ? inventoryMetrics.value.data : { error: 'unavailable' }
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch metrics' });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'frontend' });
});

const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🌐 Frontend Service running on port ${PORT}`);
});
