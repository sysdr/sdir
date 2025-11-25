#!/bin/bash

set -e

echo "🚀 Mobile Backend Architecture Demo Setup"
echo "=========================================="

# Store root directory
ROOT_DIR=$(pwd)

# Create project structure
mkdir -p mobile-backend-demo/{api-gateway,sync-service,write-queue,dashboard,tests}
cd mobile-backend-demo

# Create docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: mobiledb
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  api-gateway:
    build: ./api-gateway
    ports:
      - "3000:3000"
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://admin:password@postgres:5432/mobiledb
      - NODE_ENV=production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  sync-service:
    build: ./sync-service
    ports:
      - "3001:3001"
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://admin:password@postgres:5432/mobiledb
    depends_on:
      - postgres
      - redis

  write-queue:
    build: ./write-queue
    ports:
      - "3002:3002"
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://admin:password@postgres:5432/mobiledb
    depends_on:
      - postgres
      - redis

  dashboard:
    build: ./dashboard
    ports:
      - "8080:80"
    depends_on:
      - api-gateway

volumes:
  postgres_data:
EOF

# API Gateway Service
mkdir -p api-gateway
cat > api-gateway/package.json <<'EOF'
{
  "name": "api-gateway",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "ioredis": "^5.3.2",
    "pg": "^8.11.3",
    "express-rate-limit": "^7.1.5",
    "jsonwebtoken": "^9.0.2",
    "compression": "^1.7.4",
    "cors": "^2.8.5"
  }
}
EOF

cat > api-gateway/server.js <<'EOF'
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
EOF

cat > api-gateway/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# Sync Service
cat > sync-service/package.json <<'EOF'
{
  "name": "sync-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "pg": "^8.11.3"
  }
}
EOF

cat > sync-service/server.js <<'EOF'
import express from 'express';
import Redis from 'ioredis';
import pkg from 'pg';

const { Pool } = pkg;
const app = express();
app.use(express.json());

const redis = new Redis(process.env.REDIS_URL);
const pool = new Pool({ connectionString: process.env.POSTGRES_URL });

// Process write queue continuously
async function processWriteQueue() {
  while (true) {
    try {
      const item = await redis.brpop('write_queue', 5);
      if (!item) continue;

      const write = JSON.parse(item[1]);
      await processWrite(write);
    } catch (error) {
      console.error('Queue processing error:', error);
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

async function processWrite(write) {
  const { deviceId, key, value, vectorClock, timestamp } = write;

  // Check for conflicts using vector clocks
  const existing = await pool.query(
    'SELECT vector_clock, version FROM sync_data WHERE device_id = $1 AND data_key = $2',
    [deviceId, key]
  );

  let hasConflict = false;
  let newVersion = 1;

  if (existing.rows.length > 0) {
    const existingClock = existing.rows[0].vector_clock || {};
    hasConflict = detectConflict(existingClock, vectorClock);
    newVersion = existing.rows[0].version + 1;

    if (hasConflict) {
      await redis.incr('metrics:conflicts');
      console.log(`⚠️  Conflict detected for ${deviceId}:${key}`);
    }
  }

  // Merge vector clocks
  const mergedClock = { ...vectorClock };
  mergedClock[deviceId] = (mergedClock[deviceId] || 0) + 1;

  // Write to database
  await pool.query(`
    INSERT INTO sync_data (device_id, data_key, data_value, version, vector_clock)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (device_id, data_key) 
    DO UPDATE SET 
      data_value = $3,
      version = sync_data.version + 1,
      vector_clock = $5,
      updated_at = CURRENT_TIMESTAMP
  `, [deviceId, key, value, newVersion, JSON.stringify(mergedClock)]);

  console.log(`✅ Synced: ${deviceId}:${key} (v${newVersion})`);
}

function detectConflict(clock1, clock2) {
  const allKeys = new Set([...Object.keys(clock1), ...Object.keys(clock2)]);
  
  let clock1Ahead = false;
  let clock2Ahead = false;

  for (const key of allKeys) {
    const v1 = clock1[key] || 0;
    const v2 = clock2[key] || 0;
    
    if (v1 > v2) clock1Ahead = true;
    if (v2 > v1) clock2Ahead = true;
  }

  return clock1Ahead && clock2Ahead;
}

// Delta sync endpoint
app.post('/sync/delta', async (req, res) => {
  const { deviceId, since } = req.body;

  const result = await pool.query(
    `SELECT * FROM sync_data WHERE device_id = $1 AND updated_at > $2 ORDER BY updated_at`,
    [deviceId, since || '1970-01-01']
  );

  res.json({ delta: result.rows, count: result.rows.length });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'sync-service' });
});

processWriteQueue();

app.listen(3001, () => {
  console.log('✅ Sync Service running on port 3001');
});
EOF

cat > sync-service/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

# Write Queue Service
cat > write-queue/package.json <<'EOF'
{
  "name": "write-queue",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2"
  }
}
EOF

cat > write-queue/server.js <<'EOF'
import express from 'express';
import Redis from 'ioredis';

const app = express();
app.use(express.json());

const redis = new Redis(process.env.REDIS_URL);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'write-queue' });
});

app.get('/queue/status', async (req, res) => {
  const size = await redis.llen('write_queue');
  const metrics = {
    syncRequests: await redis.get('metrics:sync_requests') || 0,
    writesQueued: await redis.get('metrics:writes_queued') || 0,
    conflicts: await redis.get('metrics:conflicts') || 0
  };

  res.json({ queueSize: size, metrics });
});

app.listen(3002, () => {
  console.log('✅ Write Queue Service running on port 3002');
});
EOF

cat > write-queue/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY . .
EXPOSE 3002
CMD ["node", "server.js"]
EOF

# Dashboard
cat > dashboard/package.json <<'EOF'
{
  "name": "mobile-dashboard",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  }
}
EOF

cat > dashboard/vite.config.js <<'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { host: '0.0.0.0', port: 5173 },
  preview: { host: '0.0.0.0', port: 80 }
});
EOF

cat > dashboard/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mobile Backend Dashboard</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

mkdir -p dashboard/src
cat > dashboard/src/main.jsx <<'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
EOF

cat > dashboard/src/App.jsx <<'EOF'
import React, { useState, useEffect } from 'react';

export default function App() {
  const [metrics, setMetrics] = useState({ syncRequests: 0, writesQueued: 0, conflicts: 0 });
  const [devices, setDevices] = useState([]);
  const [selectedDevice, setSelectedDevice] = useState('device-1');
  const [connectionStatus, setConnectionStatus] = useState('disconnected');
  const [ws, setWs] = useState(null);
  const [logs, setLogs] = useState([]);

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    connectWebSocket();
    return () => ws?.close();
  }, [selectedDevice]);

  const fetchMetrics = async () => {
    try {
      const res = await fetch('http://localhost:3000/api/metrics');
      const data = await res.json();
      setMetrics(data);
    } catch (error) {
      console.error('Fetch metrics failed:', error);
    }
  };

  const connectWebSocket = () => {
    const websocket = new WebSocket(`ws://localhost:3000?deviceId=${selectedDevice}`);
    
    websocket.onopen = () => {
      setConnectionStatus('connected');
      addLog('✅ Connected to backend');
    };
    
    websocket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      addLog(`📨 Received: ${data.type}`);
    };
    
    websocket.onclose = () => {
      setConnectionStatus('disconnected');
      addLog('❌ Disconnected');
    };

    setWs(websocket);
  };

  const simulateOfflineWrite = async () => {
    const data = {
      deviceId: selectedDevice,
      key: `note-${Date.now()}`,
      value: `Offline note created at ${new Date().toISOString()}`,
      vectorClock: { [selectedDevice]: Math.floor(Math.random() * 10) }
    };

    try {
      const res = await fetch('http://localhost:3000/api/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      const result = await res.json();
      addLog(`✍️ Write queued: ${result.tempId}`);
    } catch (error) {
      addLog(`❌ Write failed: ${error.message}`);
    }
  };

  const simulateSync = async () => {
    try {
      const res = await fetch('http://localhost:3000/api/sync', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Cursor': '0' },
        body: JSON.stringify({ 
          deviceId: selectedDevice, 
          networkQuality: Math.random() > 0.5 ? 'high' : 'low'
        })
      });
      const result = await res.json();
      addLog(`🔄 Synced ${result.count} items (compressed: ${result.compressed})`);
    } catch (error) {
      addLog(`❌ Sync failed: ${error.message}`);
    }
  };

  const addLog = (message) => {
    setLogs(prev => [`[${new Date().toLocaleTimeString()}] ${message}`, ...prev].slice(0, 10));
  };

  return (
    <div style={{
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      minHeight: '100vh',
      padding: '20px'
    }}>
      <div style={{
        maxWidth: '1400px',
        margin: '0 auto',
        background: 'white',
        borderRadius: '16px',
        padding: '32px',
        boxShadow: '0 20px 60px rgba(0,0,0,0.3)'
      }}>
        <h1 style={{
          fontSize: '32px',
          fontWeight: '700',
          background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          marginBottom: '8px'
        }}>
          Mobile Backend Architecture
        </h1>
        <p style={{ color: '#64748b', marginBottom: '32px' }}>
          Real-time sync, optimistic writes, and conflict resolution
        </p>

        {/* Metrics */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '20px', marginBottom: '32px' }}>
          <MetricCard title="Sync Requests" value={metrics.syncRequests} color="#3b82f6" icon="🔄" />
          <MetricCard title="Writes Queued" value={metrics.writesQueued} color="#8b5cf6" icon="✍️" />
          <MetricCard title="Conflicts Resolved" value={metrics.conflicts} color="#ef4444" icon="⚠️" />
          <MetricCard 
            title="Connection Status" 
            value={connectionStatus} 
            color={connectionStatus === 'connected' ? '#10b981' : '#ef4444'} 
            icon={connectionStatus === 'connected' ? '✅' : '❌'}
          />
        </div>

        {/* Controls */}
        <div style={{
          background: '#f8fafc',
          borderRadius: '12px',
          padding: '24px',
          marginBottom: '32px'
        }}>
          <h3 style={{ fontSize: '18px', fontWeight: '600', marginBottom: '16px', color: '#1e293b' }}>
            Device Simulation
          </h3>
          
          <div style={{ display: 'flex', gap: '12px', marginBottom: '16px', flexWrap: 'wrap' }}>
            <select 
              value={selectedDevice}
              onChange={(e) => setSelectedDevice(e.target.value)}
              style={{
                padding: '12px 16px',
                borderRadius: '8px',
                border: '2px solid #e2e8f0',
                fontSize: '14px',
                fontWeight: '500',
                cursor: 'pointer'
              }}
            >
              {['device-1', 'device-2', 'device-3'].map(d => (
                <option key={d} value={d}>{d}</option>
              ))}
            </select>

            <Button onClick={simulateOfflineWrite} color="#8b5cf6">
              ✍️ Simulate Offline Write
            </Button>
            
            <Button onClick={simulateSync} color="#3b82f6">
              🔄 Trigger Sync
            </Button>
            
            <Button onClick={() => ws?.close()} color="#ef4444">
              📡 Disconnect
            </Button>
            
            <Button onClick={connectWebSocket} color="#10b981">
              🔌 Reconnect
            </Button>
          </div>
        </div>

        {/* Activity Log */}
        <div style={{
          background: '#0f172a',
          borderRadius: '12px',
          padding: '20px',
          maxHeight: '300px',
          overflow: 'auto'
        }}>
          <h3 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '12px', color: '#f1f5f9' }}>
            Activity Log
          </h3>
          {logs.map((log, i) => (
            <div key={i} style={{
              padding: '8px 12px',
              marginBottom: '4px',
              background: '#1e293b',
              borderRadius: '6px',
              color: '#e2e8f0',
              fontSize: '13px',
              fontFamily: 'Monaco, monospace'
            }}>
              {log}
            </div>
          ))}
          {logs.length === 0 && (
            <div style={{ color: '#64748b', fontSize: '14px' }}>
              No activity yet. Try simulating writes or syncs.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function MetricCard({ title, value, color, icon }) {
  return (
    <div style={{
      background: 'white',
      borderRadius: '12px',
      padding: '24px',
      border: `2px solid ${color}20`,
      boxShadow: '0 4px 6px rgba(0,0,0,0.05)'
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
        <span style={{ fontSize: '14px', color: '#64748b', fontWeight: '500' }}>{title}</span>
        <span style={{ fontSize: '24px' }}>{icon}</span>
      </div>
      <div style={{ fontSize: '32px', fontWeight: '700', color }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </div>
    </div>
  );
}

function Button({ onClick, children, color }) {
  return (
    <button
      onClick={onClick}
      style={{
        padding: '12px 20px',
        background: color,
        color: 'white',
        border: 'none',
        borderRadius: '8px',
        fontSize: '14px',
        fontWeight: '600',
        cursor: 'pointer',
        transition: 'all 0.2s',
        boxShadow: `0 4px 12px ${color}40`
      }}
      onMouseOver={(e) => e.target.style.transform = 'translateY(-2px)'}
      onMouseOut={(e) => e.target.style.transform = 'translateY(0)'}
    >
      {children}
    </button>
  );
}
EOF

cat > dashboard/Dockerfile <<'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# Test suite
cat > tests/test.sh <<'EOF'
#!/bin/bash

echo "🧪 Running Mobile Backend Tests"
echo "==============================="

# Test 1: Health checks
echo "Test 1: Health Checks"
curl -f http://localhost:3000/health || exit 1
curl -f http://localhost:3001/health || exit 1
curl -f http://localhost:3002/health || exit 1
echo "✅ All services healthy"

# Test 2: Optimistic write
echo -e "\nTest 2: Optimistic Write"
RESULT=$(curl -s -X POST http://localhost:3000/api/write \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"test-device","key":"test-key","value":"test-value","vectorClock":{"test-device":1}}')
echo $RESULT | grep -q "acknowledged" || exit 1
echo "✅ Optimistic write acknowledged"

# Test 3: Sync endpoint
echo -e "\nTest 3: Sync Request"
RESULT=$(curl -s -X POST http://localhost:3000/api/sync \
  -H "Content-Type: application/json" \
  -H "X-Cursor: 0" \
  -d '{"deviceId":"test-device","networkQuality":"high"}')
echo $RESULT | grep -q "delta" || exit 1
echo "✅ Sync endpoint working"

# Test 4: Metrics
echo -e "\nTest 4: Metrics Collection"
RESULT=$(curl -s http://localhost:3000/api/metrics)
echo $RESULT | grep -q "syncRequests" || exit 1
echo "✅ Metrics available"

# Test 5: Queue status
echo -e "\nTest 5: Queue Status"
sleep 2
RESULT=$(curl -s http://localhost:3002/queue/status)
echo $RESULT | grep -q "queueSize" || exit 1
echo "✅ Queue monitoring working"

echo -e "\n✅ All tests passed!"
EOF

chmod +x tests/test.sh

# Return to root directory to create demo.sh and cleanup.sh
cd "$ROOT_DIR"

# Create demo.sh script
cat > demo.sh <<'EOF'
#!/bin/bash

set -e

echo "🚀 Starting Mobile Backend Demo"
echo "================================"

cd mobile-backend-demo

echo ""
echo "📦 Building Docker containers..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 15

echo ""
echo "🧪 Running tests..."
bash tests/test.sh

echo ""
echo "✅ Demo Setup Complete!"
echo ""
echo "📊 Access Points:"
echo "   Dashboard:    http://localhost:8080"
echo "   API Gateway:  http://localhost:3000"
echo "   Sync Service: http://localhost:3001"
echo "   Queue Status: http://localhost:3002"
echo ""
echo "🎯 Try These Actions:"
echo "   1. Open dashboard and click 'Simulate Offline Write'"
echo "   2. Click 'Disconnect' to simulate offline mode"
echo "   3. Create multiple writes while offline"
echo "   4. Click 'Reconnect' to see sync in action"
echo "   5. Watch metrics update in real-time"
echo ""
echo "📝 View logs: docker-compose logs -f"
echo "🧹 Cleanup: ./cleanup.sh"
EOF

chmod +x demo.sh

# Create cleanup script
cat > cleanup.sh <<'EOF'
#!/bin/bash

echo "🧹 Cleaning up Mobile Backend Demo..."

cd mobile-backend-demo 2>/dev/null || true

docker-compose down -v 2>/dev/null || true

cd ..
rm -rf mobile-backend-demo

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

# Also create cleanup.sh in mobile-backend-demo for convenience
cat > mobile-backend-demo/cleanup.sh <<'EOF'
#!/bin/bash

echo "🧹 Cleaning up Mobile Backend Demo..."

docker-compose down -v 2>/dev/null || true

echo "✅ Cleanup complete!"
EOF

chmod +x mobile-backend-demo/cleanup.sh

echo ""
echo "✅ All files created successfully!"
echo ""
echo "📁 Generated Files:"
echo "   - mobile-backend-demo/ (Complete project structure)"
echo "   - demo.sh (Complete demo setup)"
echo "   - cleanup.sh (Cleanup script)"
echo ""
echo "🚀 To start the demo:"
echo "   ./demo.sh"
echo ""
echo "🧹 To cleanup:"
echo "   ./cleanup.sh"