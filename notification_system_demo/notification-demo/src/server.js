import express from 'express';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { createClient } from 'redis';
import { v4 as uuidv4 } from 'uuid';

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

app.use(express.json());
app.use(express.static('public'));

// Connect to Redis
const redis = createClient({ url: 'redis://redis:6379' });
await redis.connect();

// Stats tracking
const stats = {
  queued: 0,
  processing: 0,
  delivered: 0,
  failed: 0,
  throttled: 0,
  retrying: 0
};

// Rate limiter - Token Bucket per user
class TokenBucket {
  constructor() {
    this.buckets = new Map();
    this.capacity = 10; // 10 tokens
    this.refillRate = 2; // 2 tokens per second
  }

  async consume(userId) {
    const now = Date.now();
    let bucket = this.buckets.get(userId) || { tokens: this.capacity, lastRefill: now };
    
    // Refill tokens
    const timePassed = (now - bucket.lastRefill) / 1000;
    bucket.tokens = Math.min(this.capacity, bucket.tokens + timePassed * this.refillRate);
    bucket.lastRefill = now;
    
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      this.buckets.set(userId, bucket);
      return true;
    }
    return false;
  }
}

const rateLimiter = new TokenBucket();

// Circuit breaker for channels
class CircuitBreaker {
  constructor(threshold = 3) {
    this.failures = new Map();
    this.threshold = threshold;
    this.cooldown = 5000; // 5 seconds
  }

  async call(channel, fn) {
    const state = this.failures.get(channel) || { count: 0, openUntil: 0 };
    
    if (state.openUntil > Date.now()) {
      throw new Error(`Circuit open for ${channel}`);
    }

    try {
      const result = await fn();
      this.failures.set(channel, { count: 0, openUntil: 0 });
      return result;
    } catch (error) {
      state.count++;
      if (state.count >= this.threshold) {
        state.openUntil = Date.now() + this.cooldown;
      }
      this.failures.set(channel, state);
      throw error;
    }
  }
}

const circuitBreaker = new CircuitBreaker();

// Notification channels
const channels = {
  email: async (notification) => {
    await new Promise(resolve => setTimeout(resolve, 100));
    if (Math.random() < 0.05) throw new Error('Email service timeout');
    console.log(`📧 Email sent to ${notification.userId}: ${notification.message}`);
    return { success: true, channel: 'email' };
  },
  
  sms: async (notification) => {
    await new Promise(resolve => setTimeout(resolve, 80));
    if (Math.random() < 0.03) throw new Error('SMS gateway error');
    console.log(`📱 SMS sent to ${notification.userId}: ${notification.message}`);
    return { success: true, channel: 'sms' };
  },
  
  push: async (notification) => {
    await new Promise(resolve => setTimeout(resolve, 50));
    if (Math.random() < 0.02) throw new Error('Push service unavailable');
    console.log(`🔔 Push sent to ${notification.userId}: ${notification.message}`);
    return { success: true, channel: 'push' };
  },
  
  webhook: async (notification) => {
    await new Promise(resolve => setTimeout(resolve, 120));
    console.log(`🔗 Webhook sent to ${notification.userId}: ${notification.message}`);
    return { success: true, channel: 'webhook' };
  }
};

// Process notification with retry logic
async function processNotification(notification, attempt = 1) {
  const maxRetries = 3;
  stats.processing++;
  broadcast({ type: 'stats', data: stats });

  try {
    // Rate limiting check
    const canSend = await rateLimiter.consume(notification.userId);
    if (!canSend) {
      stats.throttled++;
      stats.processing--;
      console.log(`⚡ Throttled: ${notification.id} for user ${notification.userId}`);
      
      // Requeue after delay
      setTimeout(() => {
        redis.lPush(`queue:${notification.priority}`, JSON.stringify(notification));
      }, 2000);
      broadcast({ type: 'stats', data: stats });
      return;
    }

    // Deliver through circuit breaker
    await circuitBreaker.call(notification.channel, async () => {
      await channels[notification.channel](notification);
    });

    stats.delivered++;
    stats.processing--;
    
    broadcast({
      type: 'notification',
      data: { ...notification, status: 'delivered', timestamp: Date.now() }
    });
    
  } catch (error) {
    stats.processing--;
    
    if (attempt < maxRetries) {
      stats.retrying++;
      const backoff = Math.pow(2, attempt) * 1000;
      console.log(`🔄 Retry ${attempt} for ${notification.id} after ${backoff}ms`);
      
      setTimeout(() => {
        stats.retrying--;
        processNotification(notification, attempt + 1);
      }, backoff);
      
    } else {
      stats.failed++;
      console.log(`💀 Dead letter: ${notification.id} - ${error.message}`);
      await redis.lPush('queue:dead_letter', JSON.stringify(notification));
    }
  }
  
  broadcast({ type: 'stats', data: stats });
}

// Worker pool
async function startWorkers(count = 6) {
  const priorities = ['p0', 'p1', 'p2'];
  const workers = [];

  for (let i = 0; i < count; i++) {
    workers.push(workerLoop(i, priorities));
  }
  
  return workers;
}

async function workerLoop(workerId, priorities) {
  while (true) {
    try {
      // Check queues by priority
      for (const priority of priorities) {
        const notification = await redis.rPop(`queue:${priority}`);
        if (notification) {
          const parsed = JSON.parse(notification);
          console.log(`👷 Worker ${workerId} processing ${parsed.id} (${priority})`);
          await processNotification(parsed);
          break;
        }
      }
      await new Promise(resolve => setTimeout(resolve, 100));
    } catch (error) {
      console.error(`Worker ${workerId} error:`, error);
    }
  }
}

// WebSocket broadcast
const clients = new Set();
function broadcast(message) {
  clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(message));
    }
  });
}

wss.on('connection', (ws) => {
  clients.add(ws);
  ws.send(JSON.stringify({ type: 'stats', data: stats }));
  
  ws.on('close', () => clients.delete(ws));
});

// API endpoints
app.post('/api/notify', async (req, res) => {
  const { userId, message, priority = 'p1', channel = 'push' } = req.body;
  
  const notification = {
    id: uuidv4(),
    userId,
    message,
    priority,
    channel,
    createdAt: Date.now()
  };

  await redis.lPush(`queue:${priority}`, JSON.stringify(notification));
  stats.queued++;
  
  broadcast({ type: 'stats', data: stats });
  res.json({ success: true, id: notification.id });
});

app.get('/api/stats', (req, res) => {
  res.json(stats);
});

app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', workers: 6 });
});

// Start workers
startWorkers(6);

// Generate demo load
setInterval(async () => {
  const users = Array.from({ length: 20 }, (_, i) => `user${i}`);
  const priorities = ['p0', 'p1', 'p2'];
  const channels = ['email', 'sms', 'push', 'webhook'];
  const messages = [
    'Payment processed',
    'New message from team',
    'Weekly digest',
    'Security alert',
    'Friend request',
    'Order shipped'
  ];

  const userId = users[Math.floor(Math.random() * users.length)];
  const priority = priorities[Math.floor(Math.random() * priorities.length)];
  const channel = channels[Math.floor(Math.random() * channels.length)];
  const message = messages[Math.floor(Math.random() * messages.length)];

  const notification = {
    id: uuidv4(),
    userId,
    message,
    priority,
    channel,
    createdAt: Date.now()
  };

  await redis.lPush(`queue:${priority}`, JSON.stringify(notification));
  stats.queued++;
  broadcast({ type: 'stats', data: stats });
}, 100);

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🌐 Notification System running on http://localhost:${PORT}`);
});
