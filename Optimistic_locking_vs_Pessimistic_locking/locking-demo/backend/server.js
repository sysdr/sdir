import express from 'express';
import pg from 'pg';
import cors from 'cors';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

const pool = new pg.Pool({
  host: process.env.DB_HOST || 'postgres',
  database: 'lockingdb',
  user: 'postgres',
  password: 'postgres',
  max: 50,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

// Broadcast to all WebSocket clients
function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

// Initialize database
async function initDB() {
  await pool.query(`
    DROP TABLE IF EXISTS accounts;
    CREATE TABLE accounts (
      id SERIAL PRIMARY KEY,
      balance DECIMAL(10,2) NOT NULL DEFAULT 1000.00,
      version INTEGER NOT NULL DEFAULT 0,
      lock_holder VARCHAR(100),
      updated_at TIMESTAMP DEFAULT NOW()
    );
    INSERT INTO accounts (balance, version) VALUES (1000.00, 0);
  `);
  console.log('✅ Database initialized');
}

// Pessimistic locking: SELECT FOR UPDATE
async function pessimisticTransfer(amount, transactionId) {
  const client = await pool.connect();
  const startTime = Date.now();
  
  try {
    await client.query('BEGIN');
    
    // Acquire exclusive lock - blocks other transactions
    const lockStart = Date.now();
    const result = await client.query(
      'SELECT balance, version FROM accounts WHERE id = 1 FOR UPDATE'
    );
    const lockWaitTime = Date.now() - lockStart;
    
    const currentBalance = parseFloat(result.rows[0].balance);
    
    // Simulate processing time
    await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 50));
    
    const newBalance = currentBalance + amount;
    
    await client.query(
      'UPDATE accounts SET balance = $1, updated_at = NOW() WHERE id = 1',
      [newBalance]
    );
    
    await client.query('COMMIT');
    
    const duration = Date.now() - startTime;
    
    broadcast({
      type: 'transaction',
      mode: 'pessimistic',
      transactionId,
      success: true,
      amount,
      newBalance,
      duration,
      lockWaitTime,
      retries: 0
    });
    
    return { success: true, balance: newBalance, duration, lockWaitTime };
    
  } catch (error) {
    await client.query('ROLLBACK');
    
    broadcast({
      type: 'transaction',
      mode: 'pessimistic',
      transactionId,
      success: false,
      error: error.message,
      duration: Date.now() - startTime
    });
    
    throw error;
  } finally {
    client.release();
  }
}

// Optimistic locking: version-based
async function optimisticTransfer(amount, transactionId, maxRetries = 5) {
  let retries = 0;
  const startTime = Date.now();
  
  while (retries < maxRetries) {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');
      
      // Read without locking
      const result = await client.query(
        'SELECT balance, version FROM accounts WHERE id = 1'
      );
      
      const currentBalance = parseFloat(result.rows[0].balance);
      const currentVersion = result.rows[0].version;
      
      // Simulate processing time
      await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 50));
      
      const newBalance = currentBalance + amount;
      
      // Update only if version hasn't changed (conflict detection)
      const updateResult = await client.query(
        `UPDATE accounts 
         SET balance = $1, version = version + 1, updated_at = NOW() 
         WHERE id = 1 AND version = $2
         RETURNING balance, version`,
        [newBalance, currentVersion]
      );
      
      if (updateResult.rowCount === 0) {
        // Version mismatch - conflict detected
        await client.query('ROLLBACK');
        client.release();
        retries++;
        
        // Exponential backoff with jitter
        const backoff = Math.min(50 * Math.pow(2, retries), 500);
        const jitter = Math.random() * backoff;
        await new Promise(resolve => setTimeout(resolve, backoff + jitter));
        
        continue;
      }
      
      await client.query('COMMIT');
      const duration = Date.now() - startTime;
      
      broadcast({
        type: 'transaction',
        mode: 'optimistic',
        transactionId,
        success: true,
        amount,
        newBalance,
        duration,
        retries,
        lockWaitTime: 0
      });
      
      client.release();
      return { success: true, balance: newBalance, duration, retries };
      
    } catch (error) {
      await client.query('ROLLBACK');
      client.release();
      retries++;
      
      if (retries >= maxRetries) {
        broadcast({
          type: 'transaction',
          mode: 'optimistic',
          transactionId,
          success: false,
          error: error.message,
          duration: Date.now() - startTime,
          retries
        });
        throw error;
      }
    }
  }
  
  throw new Error('Max retries exceeded');
}

// Reset account
app.post('/api/reset', async (req, res) => {
  try {
    await pool.query(
      'UPDATE accounts SET balance = 1000.00, version = 0 WHERE id = 1'
    );
    const result = await pool.query('SELECT balance, version FROM accounts WHERE id = 1');
    
    broadcast({
      type: 'reset',
      balance: parseFloat(result.rows[0].balance),
      version: result.rows[0].version
    });
    
    res.json({ success: true, balance: result.rows[0].balance });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get current state
app.get('/api/account', async (req, res) => {
  try {
    const result = await pool.query('SELECT balance, version FROM accounts WHERE id = 1');
    res.json({
      balance: parseFloat(result.rows[0].balance),
      version: result.rows[0].version
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Run batch transactions
app.post('/api/batch', async (req, res) => {
  const { mode, count, amount } = req.body;
  
  try {
    const promises = [];
    const transferFn = mode === 'pessimistic' ? pessimisticTransfer : optimisticTransfer;
    
    for (let i = 0; i < count; i++) {
      promises.push(
        transferFn(amount, `${mode}-${Date.now()}-${i}`)
          .catch(err => ({ success: false, error: err.message }))
      );
    }
    
    const results = await Promise.all(promises);
    const successful = results.filter(r => r.success).length;
    
    broadcast({
      type: 'batch_complete',
      mode,
      total: count,
      successful,
      failed: count - successful
    });
    
    res.json({ success: true, results });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// WebSocket connection
wss.on('connection', (ws) => {
  console.log('WebSocket client connected');
  
  ws.on('close', () => {
    console.log('WebSocket client disconnected');
  });
});

// Start server
const PORT = 3001;
server.listen(PORT, async () => {
  console.log(`🚀 Backend server running on port ${PORT}`);
  await initDB();
});
