const express = require('express');
const Redis = require('ioredis');
const WebSocket = require('ws');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const redis = new Redis(process.env.REDIS_URL);
const METRICS_PREFIX = 'metrics:';

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', '*');
  next();
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

app.get('/metrics/current', async (req, res) => {
  try {
    const currentWindow = await redis.get('metrics:current_window');
    if (!currentWindow) {
      return res.json({ window: null, metrics: {} });
    }

    const windowKey = `${METRICS_PREFIX}window:${currentWindow}`;
    const metrics = await redis.hgetall(windowKey);
    const uniqueUsers = await redis.pfcount(`${windowKey}:unique_users`);
    const topPages = await redis.zrevrange(`${windowKey}:top_pages`, 0, 4, 'WITHSCORES');
    const sessionCount = await redis.scard(`${windowKey}:sessions`);

    const topPagesFormatted = [];
    for (let i = 0; i < topPages.length; i += 2) {
      topPagesFormatted.push({ page: topPages[i], views: parseInt(topPages[i + 1]) });
    }

    res.json({
      window: parseInt(currentWindow),
      windowStart: new Date(parseInt(currentWindow)).toISOString(),
      metrics: {
        totalEvents: parseInt(metrics.total_events || 0),
        uniqueUsers,
        activeSessions: sessionCount,
        topPages: topPagesFormatted
      }
    });
  } catch (error) {
    console.error('Query error:', error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics/history', async (req, res) => {
  try {
    const windows = [];
    const now = Date.now();
    const windowSize = 60000;
    
    // Get current window from Redis, or calculate from current time
    const currentWindow = await redis.get('metrics:current_window');
    let currentWindowStart;
    
    if (currentWindow) {
      currentWindowStart = parseInt(currentWindow);
    } else {
      // Calculate current window start time
      currentWindowStart = Math.floor(now / windowSize) * windowSize;
    }

    // Get last 10 windows including current (going backwards in time)
    for (let i = 0; i < 10; i++) {
      const windowStart = currentWindowStart - (i * windowSize);
      const windowKey = `${METRICS_PREFIX}window:${windowStart}`;
      
      let totalEvents = 0;
      let uniqueUsers = 0;
      
      // Check if window exists in Redis
      const exists = await redis.exists(windowKey);
      if (exists) {
        try {
          const metrics = await redis.hgetall(windowKey);
          totalEvents = parseInt(metrics.total_events || 0);
          const uniqueUsersCount = await redis.pfcount(`${windowKey}:unique_users`);
          uniqueUsers = isNaN(uniqueUsersCount) ? 0 : uniqueUsersCount;
        } catch (err) {
          console.error(`Error reading window ${windowStart}:`, err);
        }
      }
      
      // Always include window in response, even if empty
      windows.push({
        window: windowStart,
        timestamp: new Date(windowStart).toISOString(),
        totalEvents: totalEvents,
        uniqueUsers: uniqueUsers
      });
    }

    // Reverse to show oldest first, newest last
    res.json({ windows: windows.reverse() });
  } catch (error) {
    console.error('History query error:', error);
    res.status(500).json({ error: error.message });
  }
});

// WebSocket for real-time updates
wss.on('connection', (ws) => {
  console.log('WebSocket client connected');
  
  let isAlive = true;
  
  // Send ping to keep connection alive
  const pingInterval = setInterval(() => {
    if (isAlive === false) {
      clearInterval(pingInterval);
      return ws.terminate();
    }
    isAlive = false;
    ws.ping();
  }, 30000);
  
  ws.on('pong', () => {
    isAlive = true;
  });
  
  const interval = setInterval(async () => {
    try {
      if (ws.readyState !== ws.OPEN) {
        clearInterval(interval);
        clearInterval(pingInterval);
        return;
      }
      
      const currentWindow = await redis.get('metrics:current_window');
      const windowKey = currentWindow ? `${METRICS_PREFIX}window:${currentWindow}` : null;
      
      let metrics = {};
      let uniqueUsers = 0;
      let topPagesFormatted = [];
      let sessionCount = 0;
      
      if (windowKey) {
        metrics = await redis.hgetall(windowKey);
        uniqueUsers = await redis.pfcount(`${windowKey}:unique_users`);
        const topPages = await redis.zrevrange(`${windowKey}:top_pages`, 0, 4, 'WITHSCORES');
        sessionCount = await redis.scard(`${windowKey}:sessions`);

        for (let i = 0; i < topPages.length; i += 2) {
          topPagesFormatted.push({ page: topPages[i], views: parseInt(topPages[i + 1]) });
        }
      }

      const data = {
        window: currentWindow ? parseInt(currentWindow) : null,
        metrics: {
          totalEvents: parseInt(metrics.total_events || 0),
          uniqueUsers: uniqueUsers || 0,
          activeSessions: sessionCount || 0,
          topPages: topPagesFormatted
        },
        timestamp: Date.now()
      };

      ws.send(JSON.stringify(data));
    } catch (error) {
      console.error('WebSocket error:', error);
    }
  }, 1000);

  ws.on('close', () => {
    clearInterval(interval);
    clearInterval(pingInterval);
    console.log('WebSocket client disconnected');
  });
  
  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    clearInterval(interval);
    clearInterval(pingInterval);
  });
});

const PORT = 3002;
server.listen(PORT, () => console.log(`Query service running on port ${PORT}`));
