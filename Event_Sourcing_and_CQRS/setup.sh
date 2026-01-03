#!/bin/bash

echo "🚀 Setting up Event Sourcing and CQRS Demo..."

# Create directory structure
mkdir -p {command-service,projection-service,query-service,event-store,dashboard}/{src,tests}
mkdir -p shared
mkdir -p tests

# ============================================
# SHARED UTILITIES
# ============================================

cat > shared/events.js << 'EOF'
// Event types
const EventTypes = {
  ACCOUNT_CREATED: 'ACCOUNT_CREATED',
  MONEY_DEPOSITED: 'MONEY_DEPOSITED',
  MONEY_WITHDRAWN: 'MONEY_WITHDRAWN',
  MONEY_TRANSFERRED: 'MONEY_TRANSFERRED'
};

// Event factory
function createEvent(aggregateId, type, data) {
  return {
    aggregateId,
    type,
    data,
    timestamp: new Date().toISOString(),
    eventId: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
  };
}

module.exports = { EventTypes, createEvent };
EOF

# ============================================
# EVENT STORE SERVICE
# ============================================

cat > event-store/package.json << 'EOF'
{
  "name": "event-store",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "cors": "^2.8.5",
    "ws": "^8.16.0"
  }
}
EOF

cat > event-store/src/server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: 'postgres',
  port: 5432,
  database: 'eventstore',
  user: 'postgres',
  password: 'postgres'
});

// WebSocket connections for real-time event streaming
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcastEvent(event) {
  const message = JSON.stringify({ type: 'NEW_EVENT', event });
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Initialize database
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS events (
      sequence_number SERIAL PRIMARY KEY,
      event_id VARCHAR(255) UNIQUE NOT NULL,
      aggregate_id VARCHAR(255) NOT NULL,
      event_type VARCHAR(100) NOT NULL,
      event_data JSONB NOT NULL,
      timestamp TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_aggregate ON events(aggregate_id);
    CREATE INDEX IF NOT EXISTS idx_sequence ON events(sequence_number);
  `);
  console.log('Event store initialized');
}

// Append event (write operation)
app.post('/events', async (req, res) => {
  try {
    const { eventId, aggregateId, type, data, timestamp } = req.body;
    
    const result = await pool.query(
      `INSERT INTO events (event_id, aggregate_id, event_type, event_data, timestamp)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING sequence_number`,
      [eventId, aggregateId, type, JSON.stringify(data), timestamp]
    );

    const event = {
      sequenceNumber: result.rows[0].sequence_number,
      eventId,
      aggregateId,
      type,
      data,
      timestamp
    };

    // Broadcast to projection services
    broadcastEvent(event);

    res.json(event);
  } catch (error) {
    console.error('Error appending event:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get events by aggregate (for rebuilding state)
app.get('/events/:aggregateId', async (req, res) => {
  try {
    const { aggregateId } = req.params;
    const result = await pool.query(
      `SELECT * FROM events WHERE aggregate_id = $1 ORDER BY sequence_number`,
      [aggregateId]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get events from sequence number (for projection catch-up)
app.get('/events', async (req, res) => {
  try {
    const { fromSequence = 0, limit = 100 } = req.query;
    const result = await pool.query(
      `SELECT sequence_number, event_id, aggregate_id, event_type, event_data, timestamp
       FROM events 
       WHERE sequence_number > $1 
       ORDER BY sequence_number 
       LIMIT $2`,
      [fromSequence, limit]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all events (for replay)
app.get('/events/all/stream', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT sequence_number, event_id, aggregate_id, event_type, event_data, timestamp
       FROM events 
       ORDER BY sequence_number`
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3001;

async function start() {
  await initDB();
  server.listen(PORT, () => {
    console.log(`Event Store running on port ${PORT}`);
  });
}

start().catch(console.error);
EOF

cat > event-store/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
CMD ["node", "src/server.js"]
EOF

# ============================================
# COMMAND SERVICE
# ============================================

cat > command-service/package.json << 'EOF'
{
  "name": "command-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.5",
    "cors": "^2.8.5"
  }
}
EOF

cat > command-service/src/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const { EventTypes, createEvent } = require('../../shared/events');

const app = express();
app.use(cors());
app.use(express.json());

const EVENT_STORE_URL = 'http://event-store:3001';
const QUERY_SERVICE_URL = 'http://query-service:3003';

// In-memory command log for demo
const commandLog = [];

// Create account command
app.post('/commands/create-account', async (req, res) => {
  try {
    const { accountId, initialBalance = 0 } = req.body;
    
    // Validate command
    if (!accountId) {
      return res.status(400).json({ error: 'accountId required' });
    }

    // Check if account exists (via query service)
    try {
      const existing = await axios.get(`${QUERY_SERVICE_URL}/accounts/${accountId}`);
      if (existing.data) {
        return res.status(409).json({ error: 'Account already exists' });
      }
    } catch (err) {
      // Account doesn't exist, continue
    }

    // Generate event
    const event = createEvent(accountId, EventTypes.ACCOUNT_CREATED, {
      accountId,
      initialBalance
    });

    // Persist to event store
    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ command: 'CREATE_ACCOUNT', accountId, timestamp: new Date() });
    
    res.json({ success: true, event });
  } catch (error) {
    console.error('Command error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// Deposit command
app.post('/commands/deposit', async (req, res) => {
  try {
    const { accountId, amount } = req.body;
    
    if (!accountId || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid parameters' });
    }

    const event = createEvent(accountId, EventTypes.MONEY_DEPOSITED, {
      accountId,
      amount
    });

    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ command: 'DEPOSIT', accountId, amount, timestamp: new Date() });
    
    res.json({ success: true, event });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Withdraw command
app.post('/commands/withdraw', async (req, res) => {
  try {
    const { accountId, amount } = req.body;
    
    if (!accountId || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid parameters' });
    }

    // Check balance (eventual consistency - might be stale)
    const accountRes = await axios.get(`${QUERY_SERVICE_URL}/accounts/${accountId}`);
    const account = accountRes.data;
    
    if (account.balance < amount) {
      return res.status(400).json({ error: 'Insufficient funds' });
    }

    const event = createEvent(accountId, EventTypes.MONEY_WITHDRAWN, {
      accountId,
      amount
    });

    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ command: 'WITHDRAW', accountId, amount, timestamp: new Date() });
    
    res.json({ success: true, event });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Transfer command
app.post('/commands/transfer', async (req, res) => {
  try {
    const { fromAccountId, toAccountId, amount } = req.body;
    
    if (!fromAccountId || !toAccountId || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid parameters' });
    }

    // Check source balance
    const accountRes = await axios.get(`${QUERY_SERVICE_URL}/accounts/${fromAccountId}`);
    const account = accountRes.data;
    
    if (account.balance < amount) {
      return res.status(400).json({ error: 'Insufficient funds' });
    }

    const event = createEvent(fromAccountId, EventTypes.MONEY_TRANSFERRED, {
      fromAccountId,
      toAccountId,
      amount
    });

    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ 
      command: 'TRANSFER', 
      fromAccountId, 
      toAccountId, 
      amount, 
      timestamp: new Date() 
    });
    
    res.json({ success: true, event });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/commands/log', (req, res) => {
  res.json(commandLog.slice(-20));
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3002;
app.listen(PORT, () => {
  console.log(`Command Service running on port ${PORT}`);
});
EOF

cat > command-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
CMD ["node", "src/server.js"]
EOF

# ============================================
# PROJECTION SERVICE
# ============================================

cat > projection-service/package.json << 'EOF'
{
  "name": "projection-service",
  "version": "1.0.0",
  "dependencies": {
    "axios": "^1.6.5",
    "redis": "^4.6.12",
    "ws": "^8.16.0"
  }
}
EOF

cat > projection-service/src/server.js << 'EOF'
const axios = require('axios');
const redis = require('redis');
const WebSocket = require('ws');
const { EventTypes } = require('../../shared/events');

const EVENT_STORE_URL = 'http://event-store:3001';
const REDIS_URL = 'redis://redis:6379';

let redisClient;
let lastProcessedSequence = 0;
let processingStats = {
  totalProcessed: 0,
  errors: 0,
  lagMs: 0
};

async function initRedis() {
  redisClient = redis.createClient({ url: REDIS_URL });
  await redisClient.connect();
  console.log('Connected to Redis');

  // Load last processed sequence
  const saved = await redisClient.get('projection:last_sequence');
  if (saved) {
    lastProcessedSequence = parseInt(saved);
    console.log(`Resuming from sequence ${lastProcessedSequence}`);
  }
}

// Process single event and update projection
async function processEvent(event) {
  try {
    const { sequence_number, aggregate_id, event_type, event_data, timestamp } = event;
    
    // Simulate processing delay (demonstrating eventual consistency)
    await new Promise(resolve => setTimeout(resolve, 100));

    switch (event_type) {
      case EventTypes.ACCOUNT_CREATED:
        await redisClient.hSet(`account:${aggregate_id}`, {
          accountId: aggregate_id,
          balance: event_data.initialBalance.toString(),
          transactionCount: '0',
          createdAt: timestamp,
          lastUpdated: timestamp
        });
        break;

      case EventTypes.MONEY_DEPOSITED:
        const depositBalance = await redisClient.hGet(`account:${aggregate_id}`, 'balance');
        const depositCount = await redisClient.hGet(`account:${aggregate_id}`, 'transactionCount');
        await redisClient.hSet(`account:${aggregate_id}`, {
          balance: (parseFloat(depositBalance || 0) + event_data.amount).toString(),
          transactionCount: (parseInt(depositCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });
        break;

      case EventTypes.MONEY_WITHDRAWN:
        const withdrawBalance = await redisClient.hGet(`account:${aggregate_id}`, 'balance');
        const withdrawCount = await redisClient.hGet(`account:${aggregate_id}`, 'transactionCount');
        await redisClient.hSet(`account:${aggregate_id}`, {
          balance: (parseFloat(withdrawBalance || 0) - event_data.amount).toString(),
          transactionCount: (parseInt(withdrawCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });
        break;

      case EventTypes.MONEY_TRANSFERRED:
        // Update both accounts
        const fromBalance = await redisClient.hGet(`account:${event_data.fromAccountId}`, 'balance');
        const fromCount = await redisClient.hGet(`account:${event_data.fromAccountId}`, 'transactionCount');
        await redisClient.hSet(`account:${event_data.fromAccountId}`, {
          balance: (parseFloat(fromBalance || 0) - event_data.amount).toString(),
          transactionCount: (parseInt(fromCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });

        const toBalance = await redisClient.hGet(`account:${event_data.toAccountId}`, 'balance');
        const toCount = await redisClient.hGet(`account:${event_data.toAccountId}`, 'transactionCount');
        await redisClient.hSet(`account:${event_data.toAccountId}`, {
          balance: (parseFloat(toBalance || 0) + event_data.amount).toString(),
          transactionCount: (parseInt(toCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });
        break;
    }

    // Update sequence tracking
    lastProcessedSequence = sequence_number;
    await redisClient.set('projection:last_sequence', lastProcessedSequence);
    
    processingStats.totalProcessed++;
    
    // Calculate lag
    const eventTime = new Date(timestamp);
    processingStats.lagMs = Date.now() - eventTime.getTime();

    console.log(`Processed event ${sequence_number}: ${event_type}`);
  } catch (error) {
    processingStats.errors++;
    console.error('Error processing event:', error);
    throw error;
  }
}

// Catch-up: process any missed events
async function catchUp() {
  try {
    const response = await axios.get(`${EVENT_STORE_URL}/events`, {
      params: { fromSequence: lastProcessedSequence, limit: 100 }
    });

    for (const event of response.data) {
      await processEvent(event);
    }

    if (response.data.length > 0) {
      console.log(`Caught up: processed ${response.data.length} events`);
    }
  } catch (error) {
    console.error('Catch-up error:', error.message);
  }
}

// Listen for real-time events via WebSocket
function subscribeToEvents() {
  const ws = new WebSocket('ws://event-store:3001');
  
  ws.on('open', () => {
    console.log('Connected to event stream');
  });

  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data);
      if (message.type === 'NEW_EVENT') {
        await processEvent(message.event);
      }
    } catch (error) {
      console.error('WebSocket message error:', error);
    }
  });

  ws.on('close', () => {
    console.log('Event stream connection closed, reconnecting...');
    setTimeout(subscribeToEvents, 5000);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error.message);
  });
}

// Projection replay (rebuild from scratch)
async function replayProjection() {
  console.log('Starting projection replay...');
  
  // Clear existing projections
  const keys = await redisClient.keys('account:*');
  if (keys.length > 0) {
    await redisClient.del(keys);
  }
  await redisClient.set('projection:last_sequence', '0');
  lastProcessedSequence = 0;
  processingStats = { totalProcessed: 0, errors: 0, lagMs: 0 };

  // Replay all events
  const response = await axios.get(`${EVENT_STORE_URL}/events/all/stream`);
  console.log(`Replaying ${response.data.length} events...`);
  
  for (const event of response.data) {
    await processEvent(event);
  }
  
  console.log('Replay complete');
}

async function start() {
  await initRedis();
  
  // Initial catch-up
  await catchUp();
  
  // Subscribe to real-time events
  subscribeToEvents();
  
  // Periodic catch-up (in case WebSocket misses something)
  setInterval(catchUp, 5000);

  // Expose stats endpoint
  const express = require('express');
  const app = express();
  
  app.get('/stats', (req, res) => {
    res.json({
      lastProcessedSequence,
      ...processingStats
    });
  });

  app.post('/replay', async (req, res) => {
    try {
      await replayProjection();
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  app.get('/health', (req, res) => res.json({ status: 'healthy' }));

  app.listen(3004, () => {
    console.log('Projection Service stats available on port 3004');
  });
}

start().catch(console.error);
EOF

cat > projection-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
CMD ["node", "src/server.js"]
EOF

# ============================================
# QUERY SERVICE
# ============================================

cat > query-service/package.json << 'EOF'
{
  "name": "query-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.12",
    "cors": "^2.8.5"
  }
}
EOF

cat > query-service/src/server.js << 'EOF'
const express = require('express');
const redis = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const REDIS_URL = 'redis://redis:6379';
let redisClient;

async function initRedis() {
  redisClient = redis.createClient({ url: REDIS_URL });
  await redisClient.connect();
  console.log('Query Service connected to Redis');
}

// Get account by ID
app.get('/accounts/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const account = await redisClient.hGetAll(`account:${accountId}`);
    
    if (!account || Object.keys(account).length === 0) {
      return res.status(404).json({ error: 'Account not found' });
    }

    res.json({
      accountId: account.accountId,
      balance: parseFloat(account.balance),
      transactionCount: parseInt(account.transactionCount),
      createdAt: account.createdAt,
      lastUpdated: account.lastUpdated
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all accounts
app.get('/accounts', async (req, res) => {
  try {
    const keys = await redisClient.keys('account:*');
    const accounts = [];

    for (const key of keys) {
      const account = await redisClient.hGetAll(key);
      accounts.push({
        accountId: account.accountId,
        balance: parseFloat(account.balance),
        transactionCount: parseInt(account.transactionCount),
        createdAt: account.createdAt,
        lastUpdated: account.lastUpdated
      });
    }

    res.json(accounts);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3003;

async function start() {
  await initRedis();
  app.listen(PORT, () => {
    console.log(`Query Service running on port ${PORT}`);
  });
}

start().catch(console.error);
EOF

cat > query-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
CMD ["node", "src/server.js"]
EOF

# ============================================
# DASHBOARD
# ============================================

cat > dashboard/package.json << 'EOF'
{
  "name": "dashboard",
  "version": "1.0.0",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "axios": "^1.6.5"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.0.11"
  }
}
EOF

cat > dashboard/vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 3000
  }
});
EOF

cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Event Sourcing & CQRS Demo</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

cat > dashboard/src/main.jsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

cat > dashboard/src/App.jsx << 'EOF'
import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import './App.css';

const API_BASE = 'http://localhost:3002';
const QUERY_API = 'http://localhost:3003';
const EVENT_STORE = 'http://localhost:3001';
const PROJECTION_API = 'http://localhost:3004';

function App() {
  const [accounts, setAccounts] = useState([]);
  const [events, setEvents] = useState([]);
  const [projectionStats, setProjectionStats] = useState(null);
  const [commandLog, setCommandLog] = useState([]);
  const [newAccount, setNewAccount] = useState({ id: '', balance: 1000 });
  const [transaction, setTransaction] = useState({ accountId: '', amount: 0 });
  const wsRef = useRef(null);

  useEffect(() => {
    loadAccounts();
    loadEvents();
    loadCommandLog();
    loadProjectionStats();
    connectWebSocket();

    const interval = setInterval(() => {
      loadAccounts();
      loadEvents();
      loadCommandLog();
      loadProjectionStats();
    }, 2000);

    return () => {
      clearInterval(interval);
      if (wsRef.current) wsRef.current.close();
    };
  }, []);

  const connectWebSocket = () => {
    wsRef.current = new WebSocket('ws://localhost:3001');
    
    wsRef.current.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'NEW_EVENT') {
        setEvents(prev => [data.event, ...prev].slice(0, 15));
      }
    };

    wsRef.current.onclose = () => {
      setTimeout(connectWebSocket, 3000);
    };
  };

  const loadAccounts = async () => {
    try {
      const res = await axios.get(`${QUERY_API}/accounts`);
      setAccounts(res.data);
    } catch (err) {
      console.error('Error loading accounts:', err);
    }
  };

  const loadEvents = async () => {
    try {
      const res = await axios.get(`${EVENT_STORE}/events/all/stream`);
      setEvents(res.data.slice(-15).reverse());
    } catch (err) {
      console.error('Error loading events:', err);
    }
  };

  const loadCommandLog = async () => {
    try {
      const res = await axios.get(`${API_BASE}/commands/log`);
      setCommandLog(res.data.reverse());
    } catch (err) {
      console.error('Error loading command log:', err);
    }
  };

  const loadProjectionStats = async () => {
    try {
      const res = await axios.get(`${PROJECTION_API}/stats`);
      setProjectionStats(res.data);
    } catch (err) {
      console.error('Error loading projection stats:', err);
    }
  };

  const createAccount = async () => {
    try {
      await axios.post(`${API_BASE}/commands/create-account`, {
        accountId: newAccount.id,
        initialBalance: parseFloat(newAccount.balance)
      });
      setNewAccount({ id: '', balance: 1000 });
    } catch (err) {
      alert(err.response?.data?.error || 'Error creating account');
    }
  };

  const deposit = async () => {
    try {
      await axios.post(`${API_BASE}/commands/deposit`, {
        accountId: transaction.accountId,
        amount: parseFloat(transaction.amount)
      });
      setTransaction({ accountId: '', amount: 0 });
    } catch (err) {
      alert(err.response?.data?.error || 'Error depositing');
    }
  };

  const withdraw = async () => {
    try {
      await axios.post(`${API_BASE}/commands/withdraw`, {
        accountId: transaction.accountId,
        amount: parseFloat(transaction.amount)
      });
      setTransaction({ accountId: '', amount: 0 });
    } catch (err) {
      alert(err.response?.data?.error || 'Error withdrawing');
    }
  };

  const replay = async () => {
    if (!confirm('Replay projection from scratch? This will rebuild all read models.')) return;
    try {
      await axios.post(`${PROJECTION_API}/replay`);
      alert('Projection replay started! Watch the stats update.');
    } catch (err) {
      alert('Error replaying projection');
    }
  };

  return (
    <div className="app">
      <div className="header">
        <h1>⚡ Event Sourcing & CQRS</h1>
        <p className="subtitle">Watch commands flow through the CQRS pipeline in real-time</p>
      </div>

      <div className="grid">
        {/* Commands Section */}
        <div className="card">
          <h2>📝 Commands (Write Side)</h2>
          <div className="command-form">
            <h3>Create Account</h3>
            <input
              type="text"
              placeholder="Account ID"
              value={newAccount.id}
              onChange={(e) => setNewAccount({...newAccount, id: e.target.value})}
            />
            <input
              type="number"
              placeholder="Initial Balance"
              value={newAccount.balance}
              onChange={(e) => setNewAccount({...newAccount, balance: e.target.value})}
            />
            <button onClick={createAccount}>Create</button>
          </div>

          <div className="command-form">
            <h3>Transactions</h3>
            <input
              type="text"
              placeholder="Account ID"
              value={transaction.accountId}
              onChange={(e) => setTransaction({...transaction, accountId: e.target.value})}
            />
            <input
              type="number"
              placeholder="Amount"
              value={transaction.amount}
              onChange={(e) => setTransaction({...transaction, amount: e.target.value})}
            />
            <div className="button-group">
              <button onClick={deposit}>Deposit</button>
              <button onClick={withdraw}>Withdraw</button>
            </div>
          </div>

          <div className="command-log">
            <h3>Recent Commands</h3>
            {commandLog.slice(0, 8).map((cmd, i) => (
              <div key={i} className="log-entry">
                <span className="command-type">{cmd.command}</span>
                <span className="command-detail">{cmd.accountId}</span>
                {cmd.amount && <span className="command-amount">${cmd.amount}</span>}
              </div>
            ))}
          </div>
        </div>

        {/* Event Store Section */}
        <div className="card">
          <h2>📦 Event Store (Immutable Log)</h2>
          <div className="events-list">
            {events.map((event) => (
              <div key={event.event_id || event.eventId} className="event-entry">
                <div className="event-header">
                  <span className="event-type">{event.event_type || event.type}</span>
                  <span className="event-seq">#{event.sequence_number || event.sequenceNumber}</span>
                </div>
                <div className="event-data">
                  {event.aggregate_id || event.aggregateId}
                </div>
                <div className="event-time">
                  {new Date(event.timestamp).toLocaleTimeString()}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Projection Stats Section */}
        <div className="card">
          <h2>⚙️ Projection Service</h2>
          {projectionStats && (
            <div className="stats-grid">
              <div className="stat-card">
                <div className="stat-value">{projectionStats.lastProcessedSequence}</div>
                <div className="stat-label">Last Processed</div>
              </div>
              <div className="stat-card">
                <div className="stat-value">{projectionStats.totalProcessed}</div>
                <div className="stat-label">Total Processed</div>
              </div>
              <div className="stat-card">
                <div className="stat-value">{projectionStats.lagMs}ms</div>
                <div className="stat-label">Projection Lag</div>
              </div>
              <div className="stat-card">
                <div className="stat-value">{projectionStats.errors}</div>
                <div className="stat-label">Errors</div>
              </div>
            </div>
          )}
          <button className="replay-btn" onClick={replay}>🔄 Replay Projection</button>
        </div>

        {/* Query Section */}
        <div className="card">
          <h2>🔍 Query Service (Read Models)</h2>
          <div className="accounts-list">
            {accounts.map((account) => (
              <div key={account.accountId} className="account-card">
                <div className="account-header">
                  <h3>{account.accountId}</h3>
                  <div className="account-balance">${account.balance.toFixed(2)}</div>
                </div>
                <div className="account-details">
                  <span>Transactions: {account.transactionCount}</span>
                  <span className="account-time">
                    Updated: {new Date(account.lastUpdated).toLocaleTimeString()}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="info-panel">
        <h3>💡 Key Concepts</h3>
        <ul>
          <li><strong>Commands</strong> → Generate events based on business rules</li>
          <li><strong>Event Store</strong> → Immutable, append-only log of all changes</li>
          <li><strong>Projections</strong> → Asynchronously build read models from events</li>
          <li><strong>Queries</strong> → Read optimized views (eventual consistency)</li>
          <li><strong>Replay</strong> → Rebuild projections from scratch to recover or add new views</li>
        </ul>
      </div>
    </div>
  );
}

export default App;
EOF

cat > dashboard/src/App.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  padding: 20px;
}

.app {
  max-width: 1600px;
  margin: 0 auto;
}

.header {
  text-align: center;
  color: white;
  margin-bottom: 30px;
}

.header h1 {
  font-size: 2.5em;
  margin-bottom: 10px;
  text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
}

.subtitle {
  font-size: 1.1em;
  opacity: 0.9;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
  gap: 20px;
  margin-bottom: 20px;
}

.card {
  background: white;
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 10px 30px rgba(0,0,0,0.2);
}

.card h2 {
  color: #4C51BF;
  margin-bottom: 20px;
  font-size: 1.4em;
  border-bottom: 2px solid #E2E8F0;
  padding-bottom: 10px;
}

.card h3 {
  color: #2D3748;
  font-size: 1.1em;
  margin: 15px 0 10px 0;
}

.command-form {
  margin-bottom: 20px;
  padding: 15px;
  background: #F7FAFC;
  border-radius: 8px;
}

.command-form input {
  width: 100%;
  padding: 10px;
  margin: 8px 0;
  border: 2px solid #E2E8F0;
  border-radius: 6px;
  font-size: 14px;
}

.command-form input:focus {
  outline: none;
  border-color: #4C51BF;
}

.command-form button {
  width: 100%;
  padding: 12px;
  background: #4C51BF;
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.command-form button:hover {
  background: #434190;
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(76, 81, 191, 0.3);
}

.button-group {
  display: flex;
  gap: 10px;
}

.button-group button {
  flex: 1;
}

.command-log {
  max-height: 200px;
  overflow-y: auto;
}

.log-entry {
  padding: 8px 12px;
  background: white;
  border-left: 3px solid #4C51BF;
  margin: 8px 0;
  border-radius: 4px;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 14px;
}

.command-type {
  background: #4C51BF;
  color: white;
  padding: 4px 8px;
  border-radius: 4px;
  font-weight: 600;
  font-size: 12px;
}

.command-detail {
  color: #4A5568;
  flex: 1;
}

.command-amount {
  color: #38A169;
  font-weight: 600;
}

.events-list {
  max-height: 500px;
  overflow-y: auto;
}

.event-entry {
  padding: 12px;
  background: #F7FAFC;
  border-left: 4px solid #4299E1;
  margin: 10px 0;
  border-radius: 6px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.05);
}

.event-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.event-type {
  background: #4299E1;
  color: white;
  padding: 4px 10px;
  border-radius: 4px;
  font-weight: 600;
  font-size: 13px;
}

.event-seq {
  background: #E2E8F0;
  padding: 4px 8px;
  border-radius: 4px;
  font-weight: 600;
  color: #4A5568;
  font-size: 12px;
}

.event-data {
  color: #2D3748;
  font-size: 14px;
  margin: 6px 0;
}

.event-time {
  color: #718096;
  font-size: 12px;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 15px;
  margin-bottom: 20px;
}

.stat-card {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 20px;
  border-radius: 8px;
  text-align: center;
  color: white;
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
}

.stat-value {
  font-size: 2em;
  font-weight: bold;
  margin-bottom: 5px;
}

.stat-label {
  font-size: 0.9em;
  opacity: 0.9;
}

.replay-btn {
  width: 100%;
  padding: 12px;
  background: #ED8936;
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.replay-btn:hover {
  background: #DD6B20;
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(237, 137, 54, 0.3);
}

.accounts-list {
  max-height: 500px;
  overflow-y: auto;
}

.account-card {
  padding: 15px;
  background: #F7FAFC;
  border-radius: 8px;
  margin: 12px 0;
  border-left: 4px solid #48BB78;
  box-shadow: 0 2px 8px rgba(0,0,0,0.05);
}

.account-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 10px;
}

.account-header h3 {
  margin: 0;
  color: #2D3748;
  font-size: 1.1em;
}

.account-balance {
  font-size: 1.5em;
  font-weight: bold;
  color: #48BB78;
}

.account-details {
  display: flex;
  justify-content: space-between;
  color: #718096;
  font-size: 14px;
}

.account-time {
  font-style: italic;
}

.info-panel {
  background: white;
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 10px 30px rgba(0,0,0,0.2);
}

.info-panel h3 {
  color: #4C51BF;
  margin-bottom: 15px;
  font-size: 1.3em;
}

.info-panel ul {
  list-style: none;
}

.info-panel li {
  padding: 10px 0;
  border-bottom: 1px solid #E2E8F0;
  color: #4A5568;
  font-size: 15px;
}

.info-panel li:last-child {
  border-bottom: none;
}

.info-panel strong {
  color: #4C51BF;
}

/* Scrollbar styling */
::-webkit-scrollbar {
  width: 8px;
}

::-webkit-scrollbar-track {
  background: #F7FAFC;
  border-radius: 4px;
}

::-webkit-scrollbar-thumb {
  background: #CBD5E0;
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: #A0AEC0;
}
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
EOF

# ============================================
# DOCKER COMPOSE
# ============================================

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: eventstore
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
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
      timeout: 5s
      retries: 5

  event-store:
    build: ./event-store
    ports:
      - "3001:3001"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - NODE_ENV=production

  command-service:
    build: ./command-service
    ports:
      - "3002:3002"
    depends_on:
      - event-store
      - query-service
    volumes:
      - ./shared:/app/shared:ro

  query-service:
    build: ./query-service
    ports:
      - "3003:3003"
    depends_on:
      redis:
        condition: service_healthy

  projection-service:
    build: ./projection-service
    ports:
      - "3004:3004"
    depends_on:
      - event-store
      - redis
    volumes:
      - ./shared:/app/shared:ro

  dashboard:
    build: ./dashboard
    ports:
      - "3000:3000"
    depends_on:
      - command-service
      - query-service
      - event-store
      - projection-service

volumes:
  postgres-data:
EOF

# ============================================
# TEST FILE
# ============================================

cat > tests/integration.test.sh << 'EOF'
#!/bin/bash

echo "Running integration tests..."

BASE_URL="http://localhost:3002"
QUERY_URL="http://localhost:3003"

# Wait for services
sleep 5

# Test 1: Create account
echo "Test 1: Create account..."
ACCOUNT_ID="test-$(date +%s)"
curl -s -X POST ${BASE_URL}/commands/create-account \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":\"${ACCOUNT_ID}\",\"initialBalance\":1000}" | grep -q "success"

if [ $? -eq 0 ]; then
  echo "✅ Account created"
else
  echo "❌ Account creation failed"
  exit 1
fi

# Wait for projection
sleep 2

# Test 2: Query account
echo "Test 2: Query account..."
BALANCE=$(curl -s ${QUERY_URL}/accounts/${ACCOUNT_ID} | grep -o '"balance":[0-9.]*' | cut -d: -f2)
if [ "$BALANCE" = "1000" ]; then
  echo "✅ Balance correct: $BALANCE"
else
  echo "❌ Balance incorrect: $BALANCE (expected 1000)"
  exit 1
fi

# Test 3: Deposit
echo "Test 3: Deposit money..."
curl -s -X POST ${BASE_URL}/commands/deposit \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":\"${ACCOUNT_ID}\",\"amount\":500}" | grep -q "success"

if [ $? -eq 0 ]; then
  echo "✅ Deposit successful"
else
  echo "❌ Deposit failed"
  exit 1
fi

# Wait for projection
sleep 2

# Test 4: Verify new balance
echo "Test 4: Verify new balance..."
BALANCE=$(curl -s ${QUERY_URL}/accounts/${ACCOUNT_ID} | grep -o '"balance":[0-9.]*' | cut -d: -f2)
if [ "$BALANCE" = "1500" ]; then
  echo "✅ Balance correct: $BALANCE"
else
  echo "❌ Balance incorrect: $BALANCE (expected 1500)"
  exit 1
fi

# Test 5: Withdraw
echo "Test 5: Withdraw money..."
curl -s -X POST ${BASE_URL}/commands/withdraw \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":\"${ACCOUNT_ID}\",\"amount\":200}" | grep -q "success"

if [ $? -eq 0 ]; then
  echo "✅ Withdrawal successful"
else
  echo "❌ Withdrawal failed"
  exit 1
fi

# Wait for projection
sleep 2

# Test 6: Final balance
echo "Test 6: Verify final balance..."
BALANCE=$(curl -s ${QUERY_URL}/accounts/${ACCOUNT_ID} | grep -o '"balance":[0-9.]*' | cut -d: -f2)
if [ "$BALANCE" = "1300" ]; then
  echo "✅ Balance correct: $BALANCE"
else
  echo "❌ Balance incorrect: $BALANCE (expected 1300)"
  exit 1
fi

echo ""
echo "✅ All tests passed!"
EOF

chmod +x tests/integration.test.sh

# ============================================
# DEMO AND CLEANUP SCRIPTS
# ============================================

cat > demo.sh << 'EOF'
#!/bin/bash

echo "🎬 Event Sourcing & CQRS Demo"
echo "=============================="
echo ""
echo "1. Open dashboard: http://localhost:3000"
echo ""
echo "2. Try these scenarios:"
echo "   - Create accounts with different IDs"
echo "   - Make deposits and withdrawals"
echo "   - Watch events appear in real-time"
echo "   - Notice the projection lag (100ms delay)"
echo "   - Try the replay button to rebuild projections"
echo ""
echo "3. Services:"
echo "   Command Service:    http://localhost:3002"
echo "   Query Service:      http://localhost:3003"
echo "   Event Store:        http://localhost:3001"
echo "   Projection Stats:   http://localhost:3004/stats"
echo ""
echo "4. Observe eventual consistency:"
echo "   - Make a deposit"
echo "   - Immediately query the account"
echo "   - Notice the brief delay before balance updates"
echo ""
echo "Press Ctrl+C to stop watching logs..."
echo ""

docker-compose logs -f
EOF

chmod +x demo.sh

cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Event Sourcing & CQRS Demo..."

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

# ============================================
# BUILD AND RUN
# ============================================

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
echo "🧪 Running integration tests..."
./tests/integration.test.sh

echo ""
echo "✅ Setup complete!"
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo ""
echo "📖 Next steps:"
echo "   1. Open http://localhost:3000 in your browser"
echo "   2. Create some accounts and make transactions"
echo "   3. Watch events flow through the system"
echo "   4. Try the projection replay feature"
echo "   5. Run './demo.sh' to see live logs"
echo "   6. Run './cleanup.sh' when done"
echo ""