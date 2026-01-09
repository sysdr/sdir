const express = require('express');
const { WebSocketServer } = require('ws');
const { Client: PgClient } = require('pg');
const { createClient } = require('redis');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const crypto = require('crypto');

const app = express();
app.use(cors());
app.use(express.json());

// Database setup
const pgClient = new PgClient({
  host: process.env.POSTGRES_HOST || 'postgres',
  database: 'flags',
  user: 'postgres',
  password: 'postgres'
});

// Redis cache
const redisClient = createClient({ 
  url: `redis://${process.env.REDIS_HOST || 'redis'}:6379` 
});

let wsConnections = [];

// Initialize
async function init() {
  await pgClient.connect();
  await redisClient.connect();
  
  // Create tables
  await pgClient.query(`
    CREATE TABLE IF NOT EXISTS flags (
      id VARCHAR(255) PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      enabled BOOLEAN DEFAULT false,
      description TEXT,
      rollout_percentage INTEGER DEFAULT 0,
      targeting_rules JSONB,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    )
  `);
  
  await pgClient.query(`
    CREATE TABLE IF NOT EXISTS flag_evaluations (
      id SERIAL PRIMARY KEY,
      flag_id VARCHAR(255),
      user_id VARCHAR(255),
      result BOOLEAN,
      evaluated_at TIMESTAMP DEFAULT NOW()
    )
  `);
  
  // Initialize default flags
  const defaultFlags = [
    {
      id: 'new-payment-flow',
      name: 'New Payment Flow',
      enabled: true,
      rollout_percentage: 50,
      description: 'New streamlined payment experience',
      targeting_rules: { segments: ['premium', 'beta'] }
    },
    {
      id: 'recommendations-v2',
      name: 'Recommendations V2',
      enabled: true,
      rollout_percentage: 25,
      description: 'ML-powered recommendation engine',
      targeting_rules: { regions: ['US', 'CA'] }
    },
    {
      id: 'dark-mode',
      name: 'Dark Mode',
      enabled: false,
      rollout_percentage: 0,
      description: 'UI dark mode theme',
      targeting_rules: {}
    },
    {
      id: 'fast-checkout',
      name: 'Fast Checkout',
      enabled: true,
      rollout_percentage: 100,
      description: 'One-click checkout flow',
      targeting_rules: {}
    }
  ];
  
  for (const flag of defaultFlags) {
    await pgClient.query(`
      INSERT INTO flags (id, name, enabled, rollout_percentage, description, targeting_rules)
      VALUES ($1, $2, $3, $4, $5, $6)
      ON CONFLICT (id) DO NOTHING
    `, [flag.id, flag.name, flag.enabled, flag.rollout_percentage, flag.description, JSON.stringify(flag.targeting_rules)]);
  }
  
  console.log('✓ Flag service initialized');
}

// Deterministic hash for consistent user assignment
function getUserBucket(userId, flagId) {
  const hash = crypto.createHash('sha256');
  hash.update(`${userId}:${flagId}`);
  const hex = hash.digest('hex');
  return parseInt(hex.substring(0, 8), 16) % 100;
}

// Evaluate flag for user
async function evaluateFlag(flagId, userId, context = {}) {
  const cacheKey = `flag:${flagId}`;
  let flag = await redisClient.get(cacheKey);
  
  if (!flag) {
    const result = await pgClient.query('SELECT * FROM flags WHERE id = $1', [flagId]);
    if (result.rows.length === 0) return false;
    flag = result.rows[0];
    await redisClient.setEx(cacheKey, 60, JSON.stringify(flag));
  } else {
    flag = JSON.parse(flag);
  }
  
  if (!flag.enabled) return false;
  
  // Check targeting rules
  const rules = typeof flag.targeting_rules === 'string' 
    ? JSON.parse(flag.targeting_rules) 
    : flag.targeting_rules;
    
  if (rules.segments && context.segment) {
    if (!rules.segments.includes(context.segment)) return false;
  }
  
  if (rules.regions && context.region) {
    if (!rules.regions.includes(context.region)) return false;
  }
  
  // Percentage rollout using consistent hashing
  const bucket = getUserBucket(userId, flagId);
  const enabled = bucket < flag.rollout_percentage;
  
  // Log evaluation
  await pgClient.query(
    'INSERT INTO flag_evaluations (flag_id, user_id, result) VALUES ($1, $2, $3)',
    [flagId, userId, enabled]
  );
  
  return enabled;
}

// REST API
app.get('/flags', async (req, res) => {
  const result = await pgClient.query('SELECT * FROM flags ORDER BY name');
  res.json(result.rows);
});

app.get('/flags/:id', async (req, res) => {
  const result = await pgClient.query('SELECT * FROM flags WHERE id = $1', [req.params.id]);
  if (result.rows.length === 0) return res.status(404).json({ error: 'Flag not found' });
  res.json(result.rows[0]);
});

app.post('/flags/:id/toggle', async (req, res) => {
  const { id } = req.params;
  const result = await pgClient.query(
    'UPDATE flags SET enabled = NOT enabled, updated_at = NOW() WHERE id = $1 RETURNING *',
    [id]
  );
  
  if (result.rows.length === 0) return res.status(404).json({ error: 'Flag not found' });
  
  const flag = result.rows[0];
  await redisClient.del(`flag:${id}`);
  
  // Broadcast to all connected clients
  wsConnections.forEach(ws => {
    if (ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'flag_updated', flag }));
    }
  });
  
  res.json(flag);
});

app.post('/flags/:id/rollout', async (req, res) => {
  const { id } = req.params;
  const { percentage } = req.body;
  
  const result = await pgClient.query(
    'UPDATE flags SET rollout_percentage = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
    [percentage, id]
  );
  
  if (result.rows.length === 0) return res.status(404).json({ error: 'Flag not found' });
  
  const flag = result.rows[0];
  await redisClient.del(`flag:${id}`);
  
  wsConnections.forEach(ws => {
    if (ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'flag_updated', flag }));
    }
  });
  
  res.json(flag);
});

app.post('/evaluate', async (req, res) => {
  const { flagId, userId, context } = req.body;
  const enabled = await evaluateFlag(flagId, userId, context);
  res.json({ flagId, userId, enabled });
});

app.get('/stats', async (req, res) => {
  const [flags, evaluations, recentEvals] = await Promise.all([
    pgClient.query('SELECT COUNT(*) FROM flags'),
    pgClient.query('SELECT COUNT(*) FROM flag_evaluations'),
    pgClient.query(`
      SELECT flag_id, COUNT(*) as count, 
             SUM(CASE WHEN result THEN 1 ELSE 0 END) as enabled_count
      FROM flag_evaluations 
      WHERE evaluated_at > NOW() - INTERVAL '1 minute'
      GROUP BY flag_id
    `)
  ]);
  
  res.json({
    total_flags: parseInt(flags.rows[0].count),
    total_evaluations: parseInt(evaluations.rows[0].count),
    recent_evaluations: recentEvals.rows
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'flag-service' });
});

const server = app.listen(3000, async () => {
  await init();
  console.log('Flag service running on port 3000');
});

// WebSocket for real-time updates
const wss = new WebSocketServer({ server });
wss.on('connection', (ws) => {
  wsConnections.push(ws);
  console.log('Client connected to flag updates');
  
  ws.on('close', () => {
    wsConnections = wsConnections.filter(conn => conn !== ws);
  });
});
