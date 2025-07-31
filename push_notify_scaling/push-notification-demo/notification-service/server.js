const express = require('express');
const redis = require('redis');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(cors());
app.use(express.json());

// Redis clients
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.connect().catch(console.error);

// Notification templates
const templates = {
  'welcome': { title: 'Welcome!', body: 'Thanks for joining our platform' },
  'promotion': { title: 'Special Offer', body: '50% off your next purchase!' },
  'news': { title: 'Breaking News', body: 'Important update from our team' },
  'reminder': { title: 'Reminder', body: 'You have pending items' },
  'social': { title: 'New Activity', body: 'Someone interacted with your content' }
};

// Send notification endpoint
app.post('/send', async (req, res) => {
  try {
    const { type, message, targets, fanoutType = 'broadcast' } = req.body;
    
    const notificationId = uuidv4();
    const timestamp = Date.now();
    
    const notification = {
      id: notificationId,
      type,
      message: message || templates[type] || { title: 'Notification', body: 'You have a new message' },
      targets: targets || [],
      fanoutType,
      timestamp,
      status: 'sent'
    };
    
    // Store notification
    await redisClient.setEx(`notification:${notificationId}`, 3600, JSON.stringify(notification));
    
    // Publish to gateway
    await redisClient.publish('notifications', JSON.stringify(notification));
    
    console.log(`📨 Notification sent: ${notificationId} (${fanoutType})`);
    
    res.json({
      success: true,
      notificationId,
      timestamp
    });
    
  } catch (error) {
    console.error('Error sending notification:', error);
    res.status(500).json({ error: 'Failed to send notification' });
  }
});

// Bulk send endpoint
app.post('/send-bulk', async (req, res) => {
  try {
    const { notifications } = req.body;
    const results = [];
    
    for (const notificationData of notifications) {
      const notificationId = uuidv4();
      const timestamp = Date.now();
      
      const notification = {
        id: notificationId,
        ...notificationData,
        timestamp
      };
      
      await redisClient.setEx(`notification:${notificationId}`, 3600, JSON.stringify(notification));
      await redisClient.publish('notifications', JSON.stringify(notification));
      
      results.push({ id: notificationId, status: 'sent' });
    }
    
    res.json({ success: true, results });
    
  } catch (error) {
    console.error('Error sending bulk notifications:', error);
    res.status(500).json({ error: 'Failed to send bulk notifications' });
  }
});

// Get notification status
app.get('/status/:id', async (req, res) => {
  try {
    const notification = await redisClient.get(`notification:${req.params.id}`);
    if (!notification) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    
    res.json(JSON.parse(notification));
  } catch (error) {
    res.status(500).json({ error: 'Failed to get notification status' });
  }
});

// Templates endpoint
app.get('/templates', (req, res) => {
  res.json(templates);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: Date.now() });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`🚀 Notification Service running on port ${PORT}`);
});
