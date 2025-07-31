const WebSocket = require('ws');
const express = require('express');
const redis = require('redis');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Connection tracking
const connections = new Map();
const metrics = {
  totalConnections: 0,
  activeConnections: 0,
  messagesDelivered: 0,
  messagesFailed: 0,
  connectionsByRegion: {},
  deliveryLatency: []
};

// Redis client
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.connect().catch(console.error);
const subscriber = redisClient.duplicate();
subscriber.connect().catch(console.error);

// Create HTTP server
const server = require('http').createServer(app);

// WebSocket Server with connection limits
const wss = new WebSocket.Server({ 
  server,
  maxPayload: 1024 * 1024, // 1MB max payload
  perMessageDeflate: false // Disable compression for better performance
});

// Connection rate limiting
const connectionRateLimit = {
  windowMs: 60000, // 1 minute
  maxConnections: 2000, // Max connections per minute
  connections: 0,
  resetTime: Date.now()
};

// Reset connection counter every minute
setInterval(() => {
  connectionRateLimit.connections = 0;
  connectionRateLimit.resetTime = Date.now();
}, connectionRateLimit.windowMs);

wss.on('connection', (ws, request) => {
  // Check connection rate limit
  connectionRateLimit.connections++;
  if (connectionRateLimit.connections > connectionRateLimit.maxConnections) {
    console.log(`❌ Connection rate limit exceeded. Rejecting connection.`);
    ws.close(1013, 'Rate limit exceeded'); // 1013 = Try Again Later
    return;
  }
  
  const clientId = uuidv4();
  const userAgent = request.headers['user-agent'] || 'unknown';
  const region = request.headers['x-region'] || 'us-east-1';
  
  connections.set(clientId, {
    ws,
    connectedAt: Date.now(),
    region,
    userAgent,
    messagesSent: 0,
    lastActivity: Date.now()
  });
  
  metrics.totalConnections++;
  metrics.activeConnections++;
  metrics.connectionsByRegion[region] = (metrics.connectionsByRegion[region] || 0) + 1;
  
  console.log(`✅ Client ${clientId} connected from ${region}. Total: ${metrics.activeConnections}`);
  
  // Send welcome message
  ws.send(JSON.stringify({
    type: 'welcome',
    clientId,
    timestamp: Date.now()
  }));
  
  // Handle client messages
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data);
      connections.get(clientId).lastActivity = Date.now();
      
      if (message.type === 'heartbeat') {
        ws.send(JSON.stringify({ type: 'heartbeat_ack', timestamp: Date.now() }));
      }
    } catch (error) {
      console.error('Invalid message from client:', error);
    }
  });
  
  // Handle disconnection
  ws.on('close', () => {
    connections.delete(clientId);
    metrics.activeConnections--;
    metrics.connectionsByRegion[region]--;
    console.log(`❌ Client ${clientId} disconnected. Active: ${metrics.activeConnections}`);
  });
  
  // Handle errors
  ws.on('error', (error) => {
    console.error(`Client ${clientId} error:`, error);
    connections.delete(clientId);
    metrics.activeConnections--;
  });
});

// Subscribe to notification events
subscriber.subscribe('notifications', (message) => {
  try {
    const notification = JSON.parse(message);
    handleNotification(notification);
  } catch (error) {
    console.error('Error processing notification:', error);
  }
});

// Handle notification delivery
async function handleNotification(notification) {
  const { targets, message, fanoutType } = notification;
  const startTime = Date.now();
  let delivered = 0;
  let failed = 0;
  
  if (fanoutType === 'broadcast') {
    // Broadcast to all connections
    for (const [clientId, connection] of connections) {
      try {
        if (connection.ws.readyState === WebSocket.OPEN) {
          connection.ws.send(JSON.stringify({
            type: 'notification',
            message,
            timestamp: Date.now(),
            id: uuidv4()
          }));
          connection.messagesSent++;
          delivered++;
        }
      } catch (error) {
        failed++;
        console.error(`Failed to deliver to ${clientId}:`, error);
      }
    }
  } else if (fanoutType === 'targeted') {
    // Targeted delivery
    for (const targetId of targets) {
      const connection = connections.get(targetId);
      if (connection && connection.ws.readyState === WebSocket.OPEN) {
        try {
          connection.ws.send(JSON.stringify({
            type: 'notification',
            message,
            timestamp: Date.now(),
            id: uuidv4()
          }));
          connection.messagesSent++;
          delivered++;
        } catch (error) {
          failed++;
          console.error(`Failed to deliver to ${targetId}:`, error);
        }
      } else {
        failed++;
      }
    }
  }
  
  const latency = Date.now() - startTime;
  metrics.messagesDelivered += delivered;
  metrics.messagesFailed += failed;
  metrics.deliveryLatency.push(latency);
  
  // Keep only last 1000 latency measurements
  if (metrics.deliveryLatency.length > 1000) {
    metrics.deliveryLatency = metrics.deliveryLatency.slice(-1000);
  }
  
  console.log(`📤 Delivered: ${delivered}, Failed: ${failed}, Latency: ${latency}ms`);
  
  // Store delivery metrics
  await redisClient.setEx(`delivery:${Date.now()}`, 300, JSON.stringify({
    delivered,
    failed,
    latency,
    timestamp: Date.now()
  }));
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    connections: metrics.activeConnections,
    timestamp: Date.now()
  });
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  const avgLatency = metrics.deliveryLatency.length > 0 
    ? metrics.deliveryLatency.reduce((a, b) => a + b, 0) / metrics.deliveryLatency.length 
    : 0;
  
  res.json({
    ...metrics,
    averageLatency: Math.round(avgLatency),
    uptime: process.uptime()
  });
});

// Connection list endpoint
app.get('/connections', (req, res) => {
  const connectionList = Array.from(connections.entries()).map(([id, conn]) => ({
    id,
    region: conn.region,
    connectedAt: conn.connectedAt,
    messagesSent: conn.messagesSent,
    lastActivity: conn.lastActivity
  }));
  
  res.json(connectionList);
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`🚀 WebSocket Gateway starting on port ${PORT}`);
  console.log(`Redis connected to: ${process.env.REDIS_URL || 'redis://localhost:6379'}`);
});
