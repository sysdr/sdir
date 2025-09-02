const express = require('express');
const { Pool } = require('pg');
const Redis = require('redis');
const rateLimit = require('express-rate-limit');
const RedisStore = require('rate-limit-redis').default;
const cors = require('cors');
const helmet = require('helmet');
require('express-async-errors');

const app = express();
const port = 3001;

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Database connection
const db = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false
});

// Redis connection
const redisClient = Redis.createClient({
  url: process.env.REDIS_URL
});

redisClient.connect().catch(console.error);

// Tenant authentication middleware
async function authenticateUser(req, res, next) {
  const apiKey = req.headers['x-api-key'];
  
  if (!apiKey) {
    return res.status(401).json({ error: 'API key required' });
  }

  try {
    const result = await db.query(
      'SELECT u.*, t.name as tenant_name, t.rate_limit FROM users u JOIN tenants t ON u.tenant_id = t.id WHERE u.api_key = $1',
      [apiKey]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid API key' });
    }

    req.user = result.rows[0];
    req.tenantId = result.rows[0].tenant_id;
    
    // Skip RLS setup for now - use application_user connection
    next();
  } catch (error) {
    console.error('Auth error:', error);
    res.status(500).json({ error: 'Authentication failed' });
  }
}

// Dynamic rate limiting per tenant
function createTenantRateLimit() {
  return rateLimit({
    store: new RedisStore({
      sendCommand: (...args) => redisClient.sendCommand(args),
    }),
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: (req) => req.user?.rate_limit || 100,
    keyGenerator: (req) => `rate_limit:${req.tenantId}:${req.ip}`,
    message: { error: 'Rate limit exceeded for your tenant' },
    standardHeaders: true,
    legacyHeaders: false,
  });
}

// Apply authentication and rate limiting
app.use('/api', authenticateUser);
app.use('/api', createTenantRateLimit());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Get tenant info
app.get('/api/tenant', async (req, res) => {
  const result = await db.query(
    'SELECT id, name, rate_limit, max_users FROM tenants WHERE id = $1',
    [req.tenantId]
  );
  res.json(result.rows[0]);
});

// Get tasks (isolated per tenant)
app.get('/api/tasks', async (req, res) => {
  const result = await db.query(`
    SELECT t.*, u.name as user_name, u.email as user_email 
    FROM tasks t 
    JOIN users u ON t.user_id = u.id 
    WHERE t.tenant_id = $1 
    ORDER BY t.created_at DESC
  `, [req.tenantId]);
  
  res.json(result.rows);
});

// Create task
app.post('/api/tasks', async (req, res) => {
  const { title, description } = req.body;
  
  const result = await db.query(`
    INSERT INTO tasks (tenant_id, user_id, title, description) 
    VALUES ($1, $2, $3, $4) 
    RETURNING *
  `, [req.tenantId, req.user.id, title, description]);
  
  res.status(201).json(result.rows[0]);
});

// Update task
app.put('/api/tasks/:id', async (req, res) => {
  const { id } = req.params;
  const { title, description, status } = req.body;
  
  const result = await db.query(`
    UPDATE tasks 
    SET title = $1, description = $2, status = $3, updated_at = NOW() 
    WHERE id = $4 AND tenant_id = $5 
    RETURNING *
  `, [title, description, status, id, req.tenantId]);
  
  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Task not found' });
  }
  
  res.json(result.rows[0]);
});

// Delete task
app.delete('/api/tasks/:id', async (req, res) => {
  const { id } = req.params;
  
  const result = await db.query(`
    DELETE FROM tasks 
    WHERE id = $1 AND tenant_id = $2 
    RETURNING id
  `, [id, req.tenantId]);
  
  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Task not found' });
  }
  
  res.json({ message: 'Task deleted successfully' });
});

// Get isolation metrics
app.get('/api/metrics', async (req, res) => {
  try {
    const [taskCount, userCount, rateLimitInfo] = await Promise.all([
      db.query('SELECT COUNT(*) as count FROM tasks WHERE tenant_id = $1', [req.tenantId]),
      db.query('SELECT COUNT(*) as count FROM users WHERE tenant_id = $1', [req.tenantId]),
      redisClient.get(`rate_limit:${req.tenantId}:${req.ip}`)
    ]);

    res.json({
      tenant_id: req.tenantId,
      tenant_name: req.user.tenant_name,
      tasks_count: parseInt(taskCount.rows[0].count),
      users_count: parseInt(userCount.rows[0].count),
      rate_limit: req.user.rate_limit,
      current_rate_usage: rateLimitInfo ? parseInt(rateLimitInfo) : 0,
      isolation_status: 'active'
    });
  } catch (error) {
    console.error('Metrics error:', error);
    res.status(500).json({ error: 'Failed to fetch metrics' });
  }
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('Error:', error);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Tenant Isolation API running on port ${port}`);
});
