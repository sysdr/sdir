import express from 'express';
import pg from 'pg';
import { createClient } from 'redis';
import { WebSocketServer } from 'ws';
import cors from 'cors';

const { Pool } = pg;
const app = express();
app.use(express.json());
app.use(cors());

const pool = new Pool({
  host: 'postgres',
  database: 'payments',
  user: 'payment_user',
  password: 'payment_pass',
  max: 20
});

const redis = await createClient({ url: 'redis://redis:6379' })
  .on('error', err => console.log('Redis error:', err))
  .connect();

const REGION = process.env.REGION || 'processor-1';

// Initialize database
await pool.query(`
  CREATE TABLE IF NOT EXISTS payments (
    id VARCHAR(36) PRIMARY KEY,
    idempotency_key VARCHAR(36) UNIQUE NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    source_currency VARCHAR(3) NOT NULL,
    target_currency VARCHAR(3) NOT NULL,
    converted_amount DECIMAL(15,2) NOT NULL,
    locked_rate DECIMAL(10,6) NOT NULL,
    region VARCHAR(50) NOT NULL,
    state VARCHAR(20) NOT NULL,
    fraud_score DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
  );

  CREATE INDEX IF NOT EXISTS idx_state ON payments(state);
  CREATE INDEX IF NOT EXISTS idx_region ON payments(region);
  CREATE INDEX IF NOT EXISTS idx_created_at ON payments(created_at);
`);

// Fraud detection (simplified)
function calculateFraudScore(payment) {
  let score = 0.0;
  
  // High amount transactions are riskier
  if (payment.amount > 10000) score += 0.3;
  else if (payment.amount > 5000) score += 0.2;
  
  // Exotic currency pairs are riskier
  const exoticPairs = ['JPY-INR', 'INR-JPY'];
  const pair = `${payment.sourceCurrency}-${payment.targetCurrency}`;
  if (exoticPairs.includes(pair)) score += 0.2;
  
  // Random component (simulating ML model)
  score += Math.random() * 0.3;
  
  return Math.min(score, 1.0).toFixed(2);
}

// State machine transitions
const STATE_TRANSITIONS = {
  'pending': ['validated', 'rejected'],
  'validated': ['authorized', 'rejected'],
  'authorized': ['captured', 'cancelled'],
  'captured': ['settled', 'refunded'],
  'settled': ['refunded']
};

function canTransition(currentState, newState) {
  return STATE_TRANSITIONS[currentState]?.includes(newState) || false;
}

// Process payment
app.post('/api/process', async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const payment = req.body;
    const fraudScore = calculateFraudScore(payment);
    
    // Reject high fraud risk
    if (fraudScore > 0.85) {
      payment.state = 'rejected';
      await client.query(
        `INSERT INTO payments (id, idempotency_key, amount, source_currency, 
         target_currency, converted_amount, locked_rate, region, state, fraud_score)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [payment.id, payment.idempotencyKey, payment.amount, payment.sourceCurrency,
         payment.targetCurrency, payment.convertedAmount, payment.lockedRate,
         payment.region, payment.state, fraudScore]
      );
      await client.query('COMMIT');
      
      await redis.incr('metrics:total');
      
      return res.json({ ...payment, fraudScore, reason: 'High fraud risk' });
    }
    
    // Validate
    payment.state = 'validated';
    payment.fraudScore = fraudScore;
    
    // Authorize (simulate 95% success rate)
    if (Math.random() > 0.05) {
      payment.state = 'authorized';
    } else {
      payment.state = 'rejected';
    }
    
    // Capture if authorized
    if (payment.state === 'authorized') {
      payment.state = 'captured';
    }
    
    // Insert payment
    await client.query(
      `INSERT INTO payments (id, idempotency_key, amount, source_currency, 
       target_currency, converted_amount, locked_rate, region, state, fraud_score)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [payment.id, payment.idempotencyKey, payment.amount, payment.sourceCurrency,
       payment.targetCurrency, payment.convertedAmount, payment.lockedRate,
       payment.region, payment.state, fraudScore]
    );
    
    await client.query('COMMIT');
    
    // Update metrics
    await redis.incr('metrics:total');
    if (payment.state === 'captured') {
      await redis.incr('metrics:success');
    }
    
    // Publish event for real-time updates
    await redis.publish('payment-events', JSON.stringify(payment));
    
    res.json(payment);
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Process error:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// Get payment status
app.get('/api/payment/:id', async (req, res) => {
  const result = await pool.query(
    'SELECT * FROM payments WHERE id = $1',
    [req.params.id]
  );
  
  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Payment not found' });
  }
  
  res.json(result.rows[0]);
});

// Get recent payments
app.get('/api/payments', async (req, res) => {
  const limit = parseInt(req.query.limit) || 50;
  const result = await pool.query(
    'SELECT * FROM payments ORDER BY created_at DESC LIMIT $1',
    [limit]
  );
  res.json(result.rows);
});

// Get statistics
app.get('/api/stats', async (req, res) => {
  const stats = await pool.query(`
    SELECT 
      state,
      COUNT(*) as count,
      SUM(amount) as total_amount,
      AVG(fraud_score) as avg_fraud_score
    FROM payments
    GROUP BY state
  `);
  
  const byRegion = await pool.query(`
    SELECT 
      region,
      COUNT(*) as count,
      AVG(CASE WHEN state = 'captured' THEN 1 ELSE 0 END) * 100 as auth_rate
    FROM payments
    GROUP BY region
  `);
  
  res.json({
    byState: stats.rows,
    byRegion: byRegion.rows
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', region: REGION });
});

const PORT = process.env.PORT || 3001;
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`Processor [${REGION}] running on port ${PORT}`);
});

// WebSocket for real-time updates
const wss = new WebSocketServer({ server });

// Subscribe to Redis pub/sub and broadcast to WebSocket clients
const subscriber = redis.duplicate();
await subscriber.connect();

await subscriber.subscribe('payment-events', (message) => {
  wss.clients.forEach(client => {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(message);
    }
  });
});

wss.on('connection', (ws) => {
  console.log('WebSocket client connected');
  ws.on('close', () => console.log('WebSocket client disconnected'));
});
