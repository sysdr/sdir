const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());

let redisClient;
const notifications = [];

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
          const notification = {
            id: require('uuid').v4(),
            type: event.message.eventType,
            message: generateMessage(event.message.eventType, JSON.parse(event.message.data)),
            timestamp: new Date().toISOString()
          };
          
          notifications.push(notification);
          console.log(`Notification sent: ${notification.message}`);
        }
      }
    }
  } catch (error) {
    console.error('Notification processing error:', error);
  }
  setTimeout(processEvents, 100);
}

function generateMessage(eventType, data) {
  switch (eventType) {
    case 'OrderCreated':
      return `Order ${data.orderId} created for customer ${data.customerId}`;
    case 'PaymentProcessed':
      return `Payment processed for order ${data.orderId}`;
    case 'PaymentFailed':
      return `Payment failed for order ${data.orderId}`;
    default:
      return `Event: ${eventType}`;
  }
}

app.get('/notifications', (req, res) => {
  res.json(notifications.slice(-50)); // Last 50 notifications
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'notification' }));

async function init() {
  redisClient = createClient({ url: process.env.REDIS_URL });
  await redisClient.connect();
  processEvents();
  console.log('Notification Service started on port 3004');
}

app.listen(3004, init);
