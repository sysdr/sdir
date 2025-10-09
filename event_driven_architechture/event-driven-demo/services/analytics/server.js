const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());

let redisClient;
const analytics = {
  ordersCreated: 0,
  paymentsProcessed: 0,
  paymentsFailed: 0,
  totalRevenue: 0
};

async function processEvents() {
  try {
    const streams = [
      { key: 'order-events', id: '$' },
      { key: 'payment-events', id: '$' }
    ];
    
    const events = await redisClient.xRead(streams, { BLOCK: 1000 });
    
    if (events) {
      for (const stream of events) {
        for (const event of stream.messages) {
          const data = JSON.parse(event.message.data);
          
          switch (event.message.eventType) {
            case 'OrderCreated':
              analytics.ordersCreated++;
              break;
            case 'PaymentProcessed':
              analytics.paymentsProcessed++;
              analytics.totalRevenue += data.amount;
              break;
            case 'PaymentFailed':
              analytics.paymentsFailed++;
              break;
          }
        }
      }
    }
  } catch (error) {
    console.error('Analytics processing error:', error);
  }
  setTimeout(processEvents, 100);
}

app.get('/analytics', (req, res) => {
  res.json(analytics);
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'analytics' }));

async function init() {
  redisClient = createClient({ url: process.env.REDIS_URL });
  await redisClient.connect();
  processEvents();
  console.log('Analytics Service started on port 3005');
}

app.listen(3005, init);
