const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const redis = require('redis');
const axios = require('axios');
const cors = require('cors');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(express.json());
app.use(cors());
app.use(express.static(path.join(__dirname, 'public')));

const client = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
client.connect();

// WebSocket connections for real-time updates
const connections = new Set();

wss.on('connection', (ws) => {
  connections.add(ws);
  ws.on('close', () => connections.delete(ws));
});

function broadcast(data) {
  connections.forEach(ws => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(data));
    }
  });
}

// Get all debug sessions
app.get('/api/debug-sessions', async (req, res) => {
  try {
    const keys = await client.keys('debug:*');
    const sessions = keys.map(key => key.replace('debug:', ''));
    res.json(sessions);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get debug info for specific correlation ID
app.get('/api/debug/:correlationId', async (req, res) => {
  try {
    const logs = await client.lRange(`debug:${req.params.correlationId}`, 0, -1);
    const events = logs.map(log => JSON.parse(log)).reverse();
    res.json({ correlationId: req.params.correlationId, events });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create test order
app.post('/api/test-order', async (req, res) => {
  try {
    const correlationId = `test_${Date.now()}`;
    
    const response = await axios.post('http://localhost:3001/orders', {
      userId: 'user123',
      items: [
        { id: 'item1', quantity: 2 },
        { id: 'item2', quantity: 1 }
      ],
      total: 99.99
    }, {
      headers: { 'x-correlation-id': correlationId }
    });

    // Broadcast real-time update
    broadcast({
      type: 'new_order',
      correlationId,
      timestamp: new Date().toISOString()
    });

    res.json({ correlationId, result: response.data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get system health
app.get('/api/health', async (req, res) => {
  const services = [
    { name: 'Order', url: 'http://localhost:3001/health' },
    { name: 'Payment', url: 'http://localhost:3002/health' },
    { name: 'Inventory', url: 'http://localhost:3003/health' },
    { name: 'Notification', url: 'http://localhost:3004/health' }
  ];

  const healthChecks = await Promise.allSettled(
    services.map(async (service) => {
      try {
        const response = await axios.get(service.url, { timeout: 2000 });
        return { ...service, status: 'healthy', data: response.data };
      } catch (error) {
        return { ...service, status: 'unhealthy', error: error.message };
      }
    })
  );

  res.json(healthChecks.map(result => result.value));
});

server.listen(8080, () => {
  console.log('Debug dashboard running on port 8080');
});
