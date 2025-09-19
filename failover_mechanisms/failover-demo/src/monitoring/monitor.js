const express = require('express');
const WebSocket = require('ws');
const { Pool } = require('pg');
const redis = require('redis');
const fetch = require('node-fetch');
const path = require('path');

const app = express();
const port = 3000;

app.use(express.static('public'));
app.use(express.json());

// WebSocket server for real-time updates
const wss = new WebSocket.Server({ port: 8081 });

// Database connections
const primaryPool = new Pool({
  host: process.env.POSTGRES_PRIMARY_HOST || 'postgres-primary',
  port: 5432,
  database: 'ecommerce',
  user: 'admin',
  password: 'password123',
});

const secondaryPool = new Pool({
  host: process.env.POSTGRES_SECONDARY_HOST || 'postgres-secondary',
  port: 5432,
  database: 'ecommerce',
  user: 'admin',
  password: 'password123',
});

// Redis connection
const redisClient = redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'redis-master',
    port: 6379
  },
  password: 'redis123'
});

redisClient.connect().catch(console.error);

// System status monitoring
let systemStatus = {
  timestamp: new Date().toISOString(),
  databases: {
    primary: { status: 'unknown', replicationLag: 0 },
    secondary: { status: 'unknown', replicationLag: 0 }
  },
  redis: { status: 'unknown', role: 'unknown' },
  applications: {
    primary: { status: 'unknown', responseTime: 0 },
    secondary: { status: 'unknown', responseTime: 0 }
  },
  loadBalancer: { status: 'unknown', activeServers: 0 }
};

// Monitor functions
async function checkDatabaseHealth() {
  try {
    const result = await primaryPool.query('SELECT pg_is_in_recovery(), CURRENT_TIMESTAMP');
    systemStatus.databases.primary.status = 'healthy';
    systemStatus.databases.primary.inRecovery = result.rows[0].pg_is_in_recovery;
  } catch (error) {
    systemStatus.databases.primary.status = 'failed';
    systemStatus.databases.primary.error = error.message;
  }

  try {
    const result = await secondaryPool.query('SELECT pg_is_in_recovery(), CURRENT_TIMESTAMP');
    systemStatus.databases.secondary.status = 'healthy';
    systemStatus.databases.secondary.inRecovery = result.rows[0].pg_is_in_recovery;
  } catch (error) {
    systemStatus.databases.secondary.status = 'failed';
    systemStatus.databases.secondary.error = error.message;
  }
}

async function checkRedisHealth() {
  try {
    const info = await redisClient.info('replication');
    systemStatus.redis.status = 'healthy';
    systemStatus.redis.role = info.includes('role:master') ? 'master' : 'slave';
  } catch (error) {
    systemStatus.redis.status = 'failed';
    systemStatus.redis.error = error.message;
  }
}

async function checkApplicationHealth() {
  const apps = [
    { name: 'primary', url: 'http://app-primary:3001/health' },
    { name: 'secondary', url: 'http://app-secondary:3002/health' }
  ];

  for (const app of apps) {
    try {
      const startTime = Date.now();
      const response = await fetch(app.url, { timeout: 5000 });
      const responseTime = Date.now() - startTime;
      
      if (response.ok) {
        systemStatus.applications[app.name] = {
          status: 'healthy',
          responseTime: responseTime
        };
      } else {
        systemStatus.applications[app.name] = {
          status: 'unhealthy',
          responseTime: responseTime
        };
      }
    } catch (error) {
      systemStatus.applications[app.name] = {
        status: 'failed',
        error: error.message
      };
    }
  }
}

async function checkLoadBalancerHealth() {
  try {
    const response = await fetch('http://load-balancer:8404/stats;csv', { timeout: 5000 });
    if (response.ok) {
      const csvData = await response.text();
      const lines = csvData.split('\n');
      const activeServers = lines.filter(line => 
        line.includes('web_servers') && line.includes('UP')
      ).length;
      
      systemStatus.loadBalancer = {
        status: 'healthy',
        activeServers: activeServers
      };
    }
  } catch (error) {
    systemStatus.loadBalancer = {
      status: 'failed',
      error: error.message
    };
  }
}

// Monitoring loop
async function monitorSystem() {
  await Promise.all([
    checkDatabaseHealth(),
    checkRedisHealth(), 
    checkApplicationHealth(),
    checkLoadBalancerHealth()
  ]);

  systemStatus.timestamp = new Date().toISOString();

  // Broadcast to all WebSocket clients
  const message = JSON.stringify(systemStatus);
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });

  console.log('System Status:', JSON.stringify(systemStatus, null, 2));
}

// API endpoints
app.get('/api/status', (req, res) => {
  res.json(systemStatus);
});

app.post('/api/simulate-failure/:component', async (req, res) => {
  const { component } = req.params;
  
  try {
    switch (component) {
      case 'app-primary':
        await fetch('http://app-primary:3001/api/simulate-failure', { method: 'POST' });
        break;
      case 'app-secondary':
        await fetch('http://app-secondary:3002/api/simulate-failure', { method: 'POST' });
        break;
      case 'database-primary':
        // Simulate database failure by stopping container
        // This would be handled by orchestrator in real scenarios
        break;
    }
    res.json({ message: `Simulated failure for ${component}` });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// WebSocket connection handling
wss.on('connection', (ws) => {
  console.log('Client connected to monitoring WebSocket');
  ws.send(JSON.stringify(systemStatus));
  
  ws.on('close', () => {
    console.log('Client disconnected from monitoring WebSocket');
  });
});

// Serve monitoring dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(port, () => {
  console.log(`Monitoring service running on port ${port}`);
  
  // Start monitoring
  monitorSystem();
  setInterval(monitorSystem, 5000);
});
