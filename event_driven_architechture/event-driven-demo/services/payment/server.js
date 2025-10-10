const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

let redisClient;

// Payment processing
app.post('/payments', async (req, res) => {
  try {
    const { orderId, amount, paymentMethod } = req.body;
    
    // Simulate payment processing
    const success = Math.random() > 0.1; // 90% success rate
    
    const event = {
      type: success ? 'PaymentProcessed' : 'PaymentFailed',
      data: { orderId, amount, paymentMethod, transactionId: require('uuid').v4() }
    };
    
    await redisClient.xAdd('payment-events', '*', {
      eventType: event.type,
      data: JSON.stringify(event.data)
    });
    
    res.json({ 
      orderId, 
      status: success ? 'processed' : 'failed',
      transactionId: event.data.transactionId
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'payment' }));

async function init() {
  redisClient = createClient({ url: process.env.REDIS_URL });
  await redisClient.connect();
  console.log('Payment Service started on port 3003');
}

app.listen(3003, init);
