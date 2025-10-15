const express = require('express');
const axios = require('axios');
const redis = require('redis');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');

const app = express();
const port = 3000;

app.use(express.json());
app.use(cors());

// Redis client for correlation tracking
const client = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
client.connect();

// Correlation tracking
async function logEvent(correlationId, event, data) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    service: 'order-service',
    correlationId,
    event,
    data: JSON.stringify(data)
  };
  
  await client.lPush(`debug:${correlationId}`, JSON.stringify(logEntry));
  console.log(`[${correlationId}] ${event}:`, data);
}

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'order-service' });
});

// Create order with full debugging context
app.post('/orders', async (req, res) => {
  const correlationId = req.headers['x-correlation-id'] || uuidv4();
  const startTime = Date.now();
  
  try {
    await logEvent(correlationId, 'ORDER_STARTED', { 
      orderId: correlationId,
      items: req.body.items,
      userId: req.body.userId 
    });

    // Step 1: Check inventory
    await logEvent(correlationId, 'CHECKING_INVENTORY', {});
    const inventoryResponse = await axios.post('http://localhost:3003/check', {
      items: req.body.items
    }, {
      headers: { 'x-correlation-id': correlationId }
    });

    if (!inventoryResponse.data.available) {
      await logEvent(correlationId, 'INVENTORY_FAILED', inventoryResponse.data);
      return res.status(400).json({ error: 'Insufficient inventory', correlationId });
    }

    // Step 2: Process payment
    await logEvent(correlationId, 'PROCESSING_PAYMENT', {});
    const paymentResponse = await axios.post('http://localhost:3002/charge', {
      amount: req.body.total,
      userId: req.body.userId
    }, {
      headers: { 'x-correlation-id': correlationId }
    });

    if (!paymentResponse.data.success) {
      await logEvent(correlationId, 'PAYMENT_FAILED', paymentResponse.data);
      return res.status(400).json({ error: 'Payment failed', correlationId });
    }

    // Step 3: Send notification
    await logEvent(correlationId, 'SENDING_NOTIFICATION', {});
    await axios.post('http://localhost:3004/send', {
      userId: req.body.userId,
      message: 'Order confirmed'
    }, {
      headers: { 'x-correlation-id': correlationId }
    });

    const duration = Date.now() - startTime;
    await logEvent(correlationId, 'ORDER_COMPLETED', { 
      duration,
      orderId: correlationId 
    });

    res.json({ 
      success: true, 
      orderId: correlationId,
      duration,
      correlationId
    });

  } catch (error) {
    await logEvent(correlationId, 'ORDER_ERROR', { 
      error: error.message,
      stack: error.stack 
    });
    res.status(500).json({ 
      error: 'Order processing failed', 
      correlationId,
      details: error.message 
    });
  }
});

// Get debugging info for correlation ID
app.get('/debug/:correlationId', async (req, res) => {
  try {
    const logs = await client.lRange(`debug:${req.params.correlationId}`, 0, -1);
    const events = logs.map(log => JSON.parse(log)).reverse();
    res.json({ correlationId: req.params.correlationId, events });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(3001, () => {
  console.log(`Order service running on port 3001`);
});
