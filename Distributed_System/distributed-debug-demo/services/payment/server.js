const express = require('express');
const redis = require('redis');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

const client = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
client.connect();

async function logEvent(correlationId, event, data) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    service: 'payment-service',
    correlationId,
    event,
    data: JSON.stringify(data)
  };
  
  await client.lPush(`debug:${correlationId}`, JSON.stringify(logEntry));
  console.log(`[${correlationId}] ${event}:`, data);
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment-service' });
});

app.post('/charge', async (req, res) => {
  const correlationId = req.headers['x-correlation-id'];
  
  try {
    await logEvent(correlationId, 'PAYMENT_RECEIVED', {
      amount: req.body.amount,
      userId: req.body.userId
    });

    // Simulate processing time
    await new Promise(resolve => setTimeout(resolve, Math.random() * 200 + 100));

    // Simulate occasional failures for debugging
    const shouldFail = Math.random() < 0.15; // 15% failure rate
    
    if (shouldFail) {
      await logEvent(correlationId, 'PAYMENT_DECLINED', {
        reason: 'Card declined',
        amount: req.body.amount
      });
      return res.status(400).json({ 
        success: false, 
        error: 'Card declined',
        correlationId 
      });
    }

    await logEvent(correlationId, 'PAYMENT_SUCCESS', {
      transactionId: `txn_${Date.now()}`,
      amount: req.body.amount
    });

    res.json({ 
      success: true, 
      transactionId: `txn_${Date.now()}`,
      correlationId
    });

  } catch (error) {
    await logEvent(correlationId, 'PAYMENT_ERROR', { error: error.message });
    res.status(500).json({ error: error.message, correlationId });
  }
});

app.listen(3002, () => {
  console.log('Payment service running on port 3002');
});
