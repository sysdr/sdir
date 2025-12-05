const express = require('express');
const axios = require('axios');
const redis = require('redis');
const jwt = require('jsonwebtoken');
const { WebSocketServer } = require('ws');
const http = require('http');
const promClient = require('prom-client');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(express.json());
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

const JWT_SECRET = 'demo-secret-key';
const redisClient = redis.createClient({ url: process.env.REDIS_URL });

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [10, 50, 100, 200, 500, 1000, 2000]
});
register.registerMetric(httpRequestDuration);

const rateLimitCounter = new promClient.Counter({
  name: 'rate_limit_hits_total',
  help: 'Total rate limit hits',
  labelNames: ['user_id', 'endpoint']
});
register.registerMetric(rateLimitCounter);

const cacheHits = new promClient.Counter({
  name: 'cache_hits_total',
  help: 'Total cache hits',
  labelNames: ['endpoint']
});
register.registerMetric(cacheHits);

const cacheMisses = new promClient.Counter({
  name: 'cache_misses_total',
  help: 'Total cache misses',
  labelNames: ['endpoint']
});
register.registerMetric(cacheMisses);

// Connect to Redis
(async () => {
  await redisClient.connect();
  console.log('Connected to Redis');
})();

// WebSocket connections for real-time metrics
const clients = new Set();
wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcastMetrics(data) {
  clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

// Authentication Middleware (Pattern 5)
function authenticate(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }
  
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// Rate Limiting Middleware (Pattern 4)
async function rateLimit(req, res, next) {
  const userId = req.user?.userId || 'anonymous';
  const key = `ratelimit:${userId}:${req.path}`;
  const limit = 100; // requests per minute
  const window = 60; // seconds
  
  try {
    const current = await redisClient.get(key);
    
    if (current && parseInt(current) >= limit) {
      rateLimitCounter.inc({ user_id: userId, endpoint: req.path });
      return res.status(429).json({ 
        error: 'Rate limit exceeded',
        retryAfter: await redisClient.ttl(key)
      });
    }
    
    const multi = redisClient.multi();
    multi.incr(key);
    if (!current) multi.expire(key, window);
    await multi.exec();
    
    res.setHeader('X-RateLimit-Limit', limit);
    res.setHeader('X-RateLimit-Remaining', limit - (parseInt(current) || 0) - 1);
    
    next();
  } catch (error) {
    console.error('Rate limit error:', error);
    next(); // Fail open
  }
}

// Cache Middleware (Pattern 2 optimization)
function cacheMiddleware(ttl = 60) {
  return async (req, res, next) => {
    if (req.method !== 'GET') return next();
    
    const cacheKey = `cache:${req.path}:${JSON.stringify(req.query)}:${req.user?.userId}`;
    
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        cacheHits.inc({ endpoint: req.path });
        broadcastMetrics({ type: 'cache_hit', endpoint: req.path, timestamp: Date.now() });
        return res.json({ ...JSON.parse(cached), cached: true, cacheHit: true });
      }
      
      cacheMisses.inc({ endpoint: req.path });
      
      const originalJson = res.json.bind(res);
      res.json = (body) => {
        redisClient.setEx(cacheKey, ttl, JSON.stringify(body));
        return originalJson({ ...body, cached: false, cacheHit: false });
      };
      
      next();
    } catch (error) {
      console.error('Cache error:', error);
      next();
    }
  };
}

// Request Orchestration (Pattern 2)
async function orchestrateServices(userId) {
  const startTime = Date.now();
  
  const serviceConfigs = [
    { 
      name: 'user', 
      url: `${process.env.USER_SERVICE_URL}/api/user/${userId}`,
      timeout: 500,
      critical: true
    },
    { 
      name: 'orders', 
      url: `${process.env.ORDER_SERVICE_URL}/api/orders/${userId}`,
      timeout: 500,
      critical: false
    },
    { 
      name: 'analytics', 
      url: `${process.env.ANALYTICS_SERVICE_URL}/api/analytics/${userId}`,
      timeout: 500,
      critical: false
    },
    { 
      name: 'notifications', 
      url: `${process.env.NOTIFICATION_SERVICE_URL}/api/notifications/${userId}`,
      timeout: 300,
      critical: false
    }
  ];
  
  const results = await Promise.allSettled(
    serviceConfigs.map(config =>
      axios.get(config.url, { timeout: config.timeout })
        .then(response => ({ name: config.name, data: response.data, latency: Date.now() - startTime }))
        .catch(error => ({ 
          name: config.name, 
          error: error.message, 
          degraded: !config.critical 
        }))
    )
  );
  
  const response = {
    aggregated: true,
    totalLatency: Date.now() - startTime,
    services: {}
  };
  
  results.forEach((result, index) => {
    const config = serviceConfigs[index];
    if (result.status === 'fulfilled') {
      const value = result.value;
      if (value.error && !config.critical) {
        response.services[value.name] = { status: 'degraded', message: 'Service unavailable' };
      } else if (value.error) {
        throw new Error(`Critical service ${value.name} failed`);
      } else {
        response.services[value.name] = { status: 'success', data: value.data, latency: value.latency };
      }
    } else {
      if (config.critical) {
        throw new Error(`Critical service ${config.name} failed`);
      }
      response.services[config.name] = { status: 'degraded', message: 'Service timeout' };
    }
  });
  
  return response;
}

// Login endpoint - issues JWT
app.post('/api/login', (req, res) => {
  const { username } = req.body;
  
  const token = jwt.sign(
    { userId: username || 'demo-user', username: username || 'demo-user' },
    JWT_SECRET,
    { expiresIn: '24h' }
  );
  
  res.json({ token, username: username || 'demo-user' });
});

// BFF Pattern - Mobile endpoint (Pattern 1)
app.get('/api/mobile/dashboard', authenticate, rateLimit, cacheMiddleware(30), async (req, res) => {
  const end = httpRequestDuration.startTimer();
  
  try {
    const data = await orchestrateServices(req.user.userId);
    
    // Mobile optimization: reduce payload, only essential fields
    const mobileOptimized = {
      user: {
        name: data.services.user?.data?.name,
        avatar: data.services.user?.data?.avatar
      },
      recentOrders: data.services.orders?.data?.orders?.slice(0, 3),
      notificationCount: data.services.notifications?.data?.count || 0,
      performance: {
        totalLatency: data.totalLatency,
        pattern: 'BFF-Mobile'
      }
    };
    
    broadcastMetrics({ 
      type: 'request', 
      endpoint: '/api/mobile/dashboard', 
      latency: data.totalLatency,
      pattern: 'BFF-Mobile',
      timestamp: Date.now()
    });
    
    end({ method: 'GET', route: '/api/mobile/dashboard', status_code: 200 });
    res.json(mobileOptimized);
  } catch (error) {
    end({ method: 'GET', route: '/api/mobile/dashboard', status_code: 500 });
    res.status(500).json({ error: error.message });
  }
});

// BFF Pattern - Web endpoint (Pattern 1)
app.get('/api/web/dashboard', authenticate, rateLimit, cacheMiddleware(60), async (req, res) => {
  const end = httpRequestDuration.startTimer();
  
  try {
    const data = await orchestrateServices(req.user.userId);
    
    // Web optimization: full data with analytics
    const webOptimized = {
      user: data.services.user?.data,
      orders: data.services.orders?.data,
      analytics: data.services.analytics?.data,
      notifications: data.services.notifications?.data,
      metadata: {
        totalLatency: data.totalLatency,
        pattern: 'BFF-Web',
        servicesStatus: Object.entries(data.services).map(([name, service]) => ({
          name,
          status: service.status,
          latency: service.latency
        }))
      }
    };
    
    broadcastMetrics({ 
      type: 'request', 
      endpoint: '/api/web/dashboard', 
      latency: data.totalLatency,
      pattern: 'BFF-Web',
      timestamp: Date.now()
    });
    
    end({ method: 'GET', route: '/api/web/dashboard', status_code: 200 });
    res.json(webOptimized);
  } catch (error) {
    end({ method: 'GET', route: '/api/web/dashboard', status_code: 500 });
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: Date.now() });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`API Gateway running on port ${PORT}`);
  console.log(`WebSocket server running for real-time metrics`);
});
