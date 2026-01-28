import express from 'express';
import { WebSocketServer } from 'ws';
import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from 'redis';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import { createServer } from 'http';

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

// PostgreSQL connection for message storage
const pool = new Pool({
  host: 'postgres',
  port: 5432,
  database: 'chatdb',
  user: 'chatuser',
  password: 'chatpass',
  max: 20
});

// Redis connection for read receipts and presence
const redis = createClient({
  url: 'redis://redis:6379'
});

redis.on('error', (err) => console.error('Redis error:', err));

// Initialize database schema
async function initDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS messages (
      id UUID PRIMARY KEY,
      channel_id VARCHAR(100) NOT NULL,
      user_id VARCHAR(50) NOT NULL,
      username VARCHAR(50) NOT NULL,
      content TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      persisted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE INDEX IF NOT EXISTS idx_messages_channel 
    ON messages(channel_id, created_at DESC);
  `);
  
  console.log('✅ Database schema initialized');
}

// Connected clients tracking
const clients = new Map(); // wsId -> { ws, userId, username }
const userPresence = new Map(); // userId -> { status, lastSeen }

// WebSocket connection handler
wss.on('connection', (ws) => {
  const wsId = uuidv4();
  let userId = null;
  let username = null;

  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString());
      
      switch (message.type) {
        case 'join':
          userId = message.userId;
          username = message.username;
          clients.set(wsId, { ws, userId, username });
          
          // Update presence in Redis
          await redis.hSet(`presence:${userId}`, {
            status: 'online',
            lastSeen: Date.now().toString(),
            username
          });
          await redis.expire(`presence:${userId}`, 300); // 5 min TTL
          
          // Broadcast presence update
          broadcast({
            type: 'presence',
            userId,
            username,
            status: 'online',
            timestamp: Date.now()
          });
          
          console.log(`👤 ${username} joined (${userId})`);
          break;
          
        case 'message':
          // Write-through: persist to PostgreSQL first
          const startPersist = Date.now();
          const msgId = uuidv4();
          
          await pool.query(
            `INSERT INTO messages (id, channel_id, user_id, username, content) 
             VALUES ($1, $2, $3, $4, $5)`,
            [msgId, message.channelId, userId, username, message.content]
          );
          
          const persistLatency = Date.now() - startPersist;
          
          // Broadcast message to all clients
          broadcast({
            type: 'message',
            id: msgId,
            channelId: message.channelId,
            userId,
            username,
            content: message.content,
            timestamp: Date.now(),
            persistLatency
          });
          
          console.log(`💬 Message from ${username}: "${message.content}" (persisted in ${persistLatency}ms)`);
          break;
          
        case 'read':
          // Optimistic read receipt - increment Redis counter
          const readKey = `reads:${message.channelId}:${message.messageId}`;
          const readCount = await redis.incr(readKey);
          await redis.expire(readKey, 86400); // 24 hour TTL
          
          // Store user-specific read state
          await redis.hSet(`user_reads:${userId}`, message.channelId, message.messageId);
          
          // Broadcast read receipt
          broadcast({
            type: 'read_receipt',
            messageId: message.messageId,
            channelId: message.channelId,
            userId,
            username,
            readCount: parseInt(readCount),
            timestamp: Date.now()
          });
          
          console.log(`👁️  ${username} read message ${message.messageId} (total reads: ${readCount})`);
          break;
          
        case 'heartbeat':
          // Update presence TTL
          await redis.expire(`presence:${userId}`, 300);
          ws.send(JSON.stringify({ type: 'heartbeat_ack' }));
          break;
      }
    } catch (error) {
      console.error('WebSocket error:', error);
      ws.send(JSON.stringify({ type: 'error', message: error.message }));
    }
  });

  ws.on('close', async () => {
    if (userId) {
      // Update presence to offline
      await redis.hSet(`presence:${userId}`, {
        status: 'offline',
        lastSeen: Date.now().toString(),
        username
      });
      
      broadcast({
        type: 'presence',
        userId,
        username,
        status: 'offline',
        timestamp: Date.now()
      });
      
      console.log(`👋 ${username} left (${userId})`);
    }
    clients.delete(wsId);
  });
});

function broadcast(message) {
  const data = JSON.stringify(message);
  clients.forEach(({ ws }) => {
    if (ws.readyState === 1) { // OPEN
      ws.send(data);
    }
  });
}

// REST API endpoints

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: Date.now() });
});

app.get('/api/messages/:channelId', async (req, res) => {
  try {
    const { channelId } = req.params;
    const limit = parseInt(req.query.limit) || 50;
    
    const result = await pool.query(
      `SELECT * FROM messages 
       WHERE channel_id = $1 
       ORDER BY created_at DESC 
       LIMIT $2`,
      [channelId, limit]
    );
    
    res.json(result.rows.reverse());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/presence', async (req, res) => {
  try {
    const keys = await redis.keys('presence:*');
    const presence = [];
    
    for (const key of keys) {
      const data = await redis.hGetAll(key);
      if (data.username) {
        presence.push({
          userId: key.replace('presence:', ''),
          username: data.username,
          status: data.status,
          lastSeen: parseInt(data.lastSeen)
        });
      }
    }
    
    res.json(presence);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/stats', async (req, res) => {
  try {
    const messageCount = await pool.query('SELECT COUNT(*) FROM messages');
    const readKeys = await redis.keys('reads:*');
    const presenceKeys = await redis.keys('presence:*');
    
    res.json({
      totalMessages: parseInt(messageCount.rows[0].count),
      totalReadReceipts: readKeys.length,
      onlineUsers: presenceKeys.length,
      connectedClients: clients.size
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Initialize and start server
async function start() {
  try {
    await redis.connect();
    console.log('✅ Redis connected');
    
    await initDatabase();
    
    const PORT = 3001;
    server.listen(PORT, () => {
      console.log(`✅ Chat server running on port ${PORT}`);
      console.log(`   WebSocket: ws://localhost:${PORT}`);
      console.log(`   HTTP API: http://localhost:${PORT}/api`);
    });
  } catch (error) {
    console.error('❌ Startup error:', error);
    process.exit(1);
  }
}

start();
