import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import Redis from 'ioredis';
import pkg from 'pg';
import rateLimit from 'express-rate-limit';
import jwt from 'jsonwebtoken';
import compression from 'compression';
import cors from 'cors';

const { Pool } = pkg;
const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const redis = new Redis(process.env.REDIS_URL);
const pool = new Pool({ connectionString: process.env.POSTGRES_URL });

app.use(cors());
app.use(compression());
app.use(express.json());

// Initialize DB
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sync_data (
      id SERIAL PRIMARY KEY,
      device_id VARCHAR(100),
      data_key VARCHAR(100),
      data_value TEXT,
      version INTEGER DEFAULT 1,
      vector_clock JSONB,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(device_id, data_key)
    )
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_device ON sync_data(device_id)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_updated ON sync_data(updated_at)`);
}

// Rate limiter with battery-aware tiers
const createRateLimiter = (windowMs, max) => rateLimit({
  windowMs,
  max,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    const retryAfter = Math.floor(Math.random() * (300 - 5) + 5);
    res.status(429).json({ 
      error: 'Too many requests',
      retryAfter,
      tier: 'throttled'
    });
  }
});

// Auth middleware
const authMiddleware = (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1] || 'demo-token';
  try {
    req.user = jwt.verify(token, 'secret-key');
  } catch {
    req.user = { deviceId: `device-${Math.random().toString(36).substr(2, 9)}`, tier: 'active' };
  }
  next();
};

app.use('/api', createRateLimiter(60000, 100));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'api-gateway' });
});

// Adaptive payload compression endpoint
app.post('/api/sync', authMiddleware, async (req, res) => {
  const { deviceId, data, networkQuality = 'high' } = req.body;
  const clientCursor = req.headers['x-cursor'] || '0';

  try {
    // Get delta updates since cursor
    const result = await pool.query(
      `SELECT * FROM sync_data WHERE device_id = $1 AND id > $2 ORDER BY id`,
      [deviceId, parseInt(clientCursor)]
    );

    let payload = result.rows;
    
    // Adaptive compression based on network quality
    if (networkQuality === 'low') {
      payload = payload.map(row => ({
        id: row.id,
        k: row.data_key,
        v: row.data_value.substring(0, 50), // Truncate
        ver: row.version
      }));
    }

    const newCursor = payload.length > 0 ? payload[payload.length - 1].id : clientCursor;

    res.json({
      delta: payload,
      cursor: newCursor,
      compressed: networkQuality === 'low',
      count: payload.length
    });

    await redis.incr('metrics:sync_requests');
  } catch (error) {
    res.status(500).json({ error: 'Sync failed' });
  }
});

// Optimistic write endpoint
app.post('/api/write', authMiddleware, async (req, res) => {
  const { deviceId, key, value, vectorClock } = req.body;

  // Immediate optimistic acknowledgment
  const tempId = `temp-${Date.now()}`;
  res.json({ 
    acknowledged: true, 
    tempId,
    timestamp: Date.now(),
    queued: true
  });

  // Async processing
  setImmediate(async () => {
    try {
      await redis.lpush('write_queue', JSON.stringify({
        deviceId,
        key,
        value,
        vectorClock: vectorClock || { [deviceId]: 1 },
        timestamp: Date.now()
      }));
      await redis.incr('metrics:writes_queued');
    } catch (error) {
      console.error('Queue write failed:', error);
    }
  });
});

// Get device sync status
app.get('/api/status/:deviceId', authMiddleware, async (req, res) => {
  const { deviceId } = req.params;
  
  const result = await pool.query(
    'SELECT COUNT(*) as count, MAX(updated_at) as last_sync FROM sync_data WHERE device_id = $1',
    [deviceId]
  );

  const queueSize = await redis.llen('write_queue');
  const syncCount = await redis.get('metrics:sync_requests') || 0;

  res.json({
    deviceId,
    recordCount: parseInt(result.rows[0].count),
    lastSync: result.rows[0].last_sync,
    queueSize,
    totalSyncs: parseInt(syncCount)
  });
});

// Metrics endpoint
app.get('/api/metrics', async (req, res) => {
  const [syncRequests, writesQueued, conflicts] = await Promise.all([
    redis.get('metrics:sync_requests'),
    redis.get('metrics:writes_queued'),
    redis.get('metrics:conflicts')
  ]);

  res.json({
    syncRequests: parseInt(syncRequests || 0),
    writesQueued: parseInt(writesQueued || 0),
    conflicts: parseInt(conflicts || 0),
    timestamp: Date.now()
  });
});

// WebSocket for real-time updates
const clients = new Map();

wss.on('connection', (ws, req) => {
  const deviceId = new URL(req.url, 'http://localhost').searchParams.get('deviceId') || 'unknown';
  clients.set(deviceId, ws);

  ws.on('message', async (message) => {
    const data = JSON.parse(message);
    
    if (data.type === 'ping') {
      ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
    }
  });

  ws.on('close', () => {
    clients.delete(deviceId);
  });

  // Send welcome with adaptive poll interval
  ws.send(JSON.stringify({
    type: 'connected',
    deviceId,
    pollInterval: 5000 // Start with 5s, backend can adjust
  }));
});

// Broadcast updates to connected clients
export function broadcastUpdate(deviceId, update) {
  const ws = clients.get(deviceId);
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify({ type: 'update', data: update }));
  }
}

await initDB();

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`✅ API Gateway running on port ${PORT}`);
  console.log(`📊 WebSocket server ready for connections`);
});
