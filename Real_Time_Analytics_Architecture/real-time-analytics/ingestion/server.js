const express = require('express');
const Redis = require('ioredis');
const { createHash } = require('crypto');

const app = express();
app.use(express.json());

const redis = new Redis(process.env.REDIS_URL);
const STREAM_KEY = 'clickstream:events';

// Health check
app.get('/health', (req, res) => res.json({ status: 'healthy' }));

// Ingest clickstream events
app.post('/events', async (req, res) => {
  try {
    const { userId, page, timestamp = Date.now(), sessionId } = req.body;
    
    if (!userId || !page) {
      return res.status(400).json({ error: 'userId and page required' });
    }

    const event = {
      userId,
      page,
      timestamp,
      sessionId: sessionId || createHash('md5').update(`${userId}-${Date.now()}`).digest('hex'),
      eventId: createHash('md5').update(`${userId}-${page}-${timestamp}`).digest('hex')
    };

    // Add to Redis Stream
    await redis.xadd(
      STREAM_KEY,
      '*',
      'userId', event.userId,
      'page', event.page,
      'timestamp', event.timestamp,
      'sessionId', event.sessionId,
      'eventId', event.eventId
    );

    res.json({ success: true, eventId: event.eventId });
  } catch (error) {
    console.error('Ingestion error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Generate synthetic load for testing
app.post('/generate-load', async (req, res) => {
  const { count = 100, ratePerSecond = 10 } = req.body;
  const pages = ['/home', '/product', '/checkout', '/profile', '/search'];
  
  let generated = 0;
  const interval = 1000 / ratePerSecond;
  
  const generateBatch = async () => {
    if (generated >= count) {
      return res.json({ success: true, generated });
    }

    const userId = `user_${Math.floor(Math.random() * 1000)}`;
    const page = pages[Math.floor(Math.random() * pages.length)];
    
    try {
      await redis.xadd(
        STREAM_KEY,
        '*',
        'userId', userId,
        'page', page,
        'timestamp', Date.now().toString(),
        'sessionId', createHash('md5').update(`${userId}-session`).digest('hex'),
        'eventId', createHash('md5').update(`${userId}-${page}-${Date.now()}`).digest('hex')
      );
      generated++;
      setTimeout(generateBatch, interval);
    } catch (error) {
      console.error('Generation error:', error);
    }
  };

  generateBatch();
});

const PORT = 3001;
app.listen(PORT, () => console.log(`Ingestion service running on port ${PORT}`));
