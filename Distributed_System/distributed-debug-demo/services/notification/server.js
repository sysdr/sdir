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
    service: 'notification-service',
    correlationId,
    event,
    data: JSON.stringify(data)
  };
  
  await client.lPush(`debug:${correlationId}`, JSON.stringify(logEntry));
  console.log(`[${correlationId}] ${event}:`, data);
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'notification-service' });
});

app.post('/send', async (req, res) => {
  const correlationId = req.headers['x-correlation-id'];
  
  try {
    await logEvent(correlationId, 'NOTIFICATION_START', {
      userId: req.body.userId,
      message: req.body.message
    });

    // Simulate processing time
    await new Promise(resolve => setTimeout(resolve, Math.random() * 150 + 50));

    await logEvent(correlationId, 'NOTIFICATION_SENT', {
      userId: req.body.userId,
      channel: 'email',
      messageId: `msg_${Date.now()}`
    });

    res.json({ 
      success: true, 
      messageId: `msg_${Date.now()}`,
      correlationId
    });

  } catch (error) {
    await logEvent(correlationId, 'NOTIFICATION_ERROR', { error: error.message });
    res.status(500).json({ error: error.message, correlationId });
  }
});

app.listen(3004, () => {
  console.log('Notification service running on port 3004');
});
