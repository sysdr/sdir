const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const http = require('http');
const WebSocket = require('ws');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: 'postgres',
  port: 5432,
  database: 'gdpr_db',
  user: 'postgres',
  password: 'postgres'
});

const redisClient = redis.createClient({ url: 'redis://redis:6379' });
redisClient.connect();

// Broadcast to all WebSocket clients
function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

// Pseudonymization helper
function pseudonymize(data) {
  const hash = crypto.createHash('sha256').update(data).digest('hex').substring(0, 16);
  return `PSEUDO_${hash}`;
}

// Initialize database
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      name VARCHAR(255),
      phone VARCHAR(50),
      created_at TIMESTAMP DEFAULT NOW(),
      data_residency VARCHAR(10) DEFAULT 'EU',
      is_deleted BOOLEAN DEFAULT FALSE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS consent_events (
      id SERIAL PRIMARY KEY,
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      consent_type VARCHAR(50),
      status VARCHAR(20),
      version INTEGER,
      timestamp TIMESTAMP DEFAULT NOW()
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS audit_log (
      id SERIAL PRIMARY KEY,
      user_id UUID,
      action VARCHAR(50),
      details JSONB,
      timestamp TIMESTAMP DEFAULT NOW(),
      ip_address VARCHAR(50)
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS deletion_queue (
      id SERIAL PRIMARY KEY,
      user_id UUID,
      status VARCHAR(20) DEFAULT 'pending',
      subsystems_completed JSONB DEFAULT '[]',
      total_subsystems INTEGER DEFAULT 5,
      started_at TIMESTAMP DEFAULT NOW(),
      completed_at TIMESTAMP
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_analytics (
      id SERIAL PRIMARY KEY,
      user_id UUID,
      event_type VARCHAR(100),
      event_data JSONB,
      pseudonymized_id VARCHAR(50),
      timestamp TIMESTAMP DEFAULT NOW(),
      retention_until TIMESTAMP
    )
  `);
}

// Create audit log entry
async function auditLog(userId, action, details, ip = '127.0.0.1') {
  await pool.query(
    'INSERT INTO audit_log (user_id, action, details, ip_address) VALUES ($1, $2, $3, $4)',
    [userId, action, JSON.stringify(details), ip]
  );
  broadcast({ type: 'audit', action, userId, details, timestamp: new Date() });
}

// GDPR Endpoints

// Create user with consent
app.post('/api/users', async (req, res) => {
  const { email, name, phone, consents } = req.body;
  const userId = uuidv4();
  
  try {
    await pool.query(
      'INSERT INTO users (id, email, name, phone) VALUES ($1, $2, $3, $4)',
      [userId, email, name, phone]
    );

    // Record consent events
    for (const [type, status] of Object.entries(consents || {})) {
      await pool.query(
        'INSERT INTO consent_events (user_id, consent_type, status, version) VALUES ($1, $2, $3, 1)',
        [userId, type, status ? 'granted' : 'denied']
      );
    }

    // Store in cache with TTL
    await redisClient.setEx(`user:${userId}`, 3600, JSON.stringify({ email, name, phone }));

    // Create analytics with pseudonymized ID
    const pseudoId = pseudonymize(userId);
    await pool.query(
      'INSERT INTO user_analytics (user_id, event_type, pseudonymized_id, retention_until) VALUES ($1, $2, $3, NOW() + INTERVAL \'90 days\')',
      [userId, 'user_created', pseudoId]
    );

    await auditLog(userId, 'USER_CREATED', { email, consents });

    res.json({ userId, message: 'User created with consent tracking' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all users
app.get('/api/users', async (req, res) => {
  try {
    const users = await pool.query(
      'SELECT id, email, name, phone, created_at FROM users WHERE is_deleted = FALSE ORDER BY created_at DESC'
    );
    res.json(users.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get user data (Right to Access)
app.get('/api/users/:userId', async (req, res) => {
  const { userId } = req.params;

  try {
    const user = await pool.query('SELECT * FROM users WHERE id = $1 AND is_deleted = FALSE', [userId]);
    if (user.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const consents = await pool.query(
      'SELECT DISTINCT ON (consent_type) * FROM consent_events WHERE user_id = $1 ORDER BY consent_type, timestamp DESC',
      [userId]
    );

    const analytics = await pool.query(
      'SELECT event_type, timestamp, pseudonymized_id FROM user_analytics WHERE user_id = $1',
      [userId]
    );

    await auditLog(userId, 'DATA_ACCESS', { type: 'subject_access_request' });

    res.json({
      user: user.rows[0],
      consents: consents.rows,
      analytics: analytics.rows
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update consent (Consent Management)
app.post('/api/users/:userId/consent', async (req, res) => {
  const { userId } = req.params;
  const { consentType, status } = req.body;

  try {
    const version = await pool.query(
      'SELECT COALESCE(MAX(version), 0) + 1 as next_version FROM consent_events WHERE user_id = $1 AND consent_type = $2',
      [userId, consentType]
    );

    await pool.query(
      'INSERT INTO consent_events (user_id, consent_type, status, version) VALUES ($1, $2, $3, $4)',
      [userId, consentType, status ? 'granted' : 'withdrawn', version.rows[0].next_version]
    );

    await auditLog(userId, 'CONSENT_UPDATED', { consentType, status, version: version.rows[0].next_version });

    broadcast({ type: 'consent_change', userId, consentType, status });

    res.json({ message: 'Consent updated', version: version.rows[0].next_version });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete user data (Right to Erasure)
app.delete('/api/users/:userId', async (req, res) => {
  const { userId } = req.params;

  try {
    // Create deletion queue entry
    const queueEntry = await pool.query(
      'INSERT INTO deletion_queue (user_id, status) VALUES ($1, $2) RETURNING id',
      [userId, 'processing']
    );

    const deletionId = queueEntry.rows[0].id;
    const subsystems = ['database', 'cache', 'analytics', 'backups', 'logs'];
    let completed = [];

    // Simulate propagation through subsystems
    for (const subsystem of subsystems) {
      await new Promise(resolve => setTimeout(resolve, 500));
      
      switch(subsystem) {
        case 'database':
          await pool.query('UPDATE users SET is_deleted = TRUE WHERE id = $1', [userId]);
          break;
        case 'cache':
          await redisClient.del(`user:${userId}`);
          break;
        case 'analytics':
          await pool.query('DELETE FROM user_analytics WHERE user_id = $1', [userId]);
          break;
        case 'backups':
          // Simulate backup cleanup
          break;
        case 'logs':
          // Anonymize logs
          await pool.query(
            'UPDATE audit_log SET user_id = NULL WHERE user_id = $1',
            [userId]
          );
          break;
      }

      completed.push(subsystem);
      await pool.query(
        'UPDATE deletion_queue SET subsystems_completed = $1 WHERE id = $2',
        [JSON.stringify(completed), deletionId]
      );

      broadcast({ 
        type: 'deletion_progress', 
        userId, 
        subsystem, 
        completed: completed.length,
        total: subsystems.length 
      });
    }

    // Mark as completed
    await pool.query(
      'UPDATE deletion_queue SET status = $1, completed_at = NOW() WHERE id = $2',
      ['completed', deletionId]
    );

    await auditLog(userId, 'USER_DELETED', { deletionId, subsystems: completed });

    res.json({ 
      message: 'User deletion completed',
      deletionId,
      subsystemsProcessed: completed
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Data portability (Right to Data Portability)
app.get('/api/users/:userId/export', async (req, res) => {
  const { userId } = req.params;

  try {
    const user = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
    const consents = await pool.query('SELECT * FROM consent_events WHERE user_id = $1', [userId]);
    const analytics = await pool.query('SELECT * FROM user_analytics WHERE user_id = $1', [userId]);

    const exportData = {
      user: user.rows[0],
      consents: consents.rows,
      analytics: analytics.rows,
      exportDate: new Date(),
      format: 'JSON'
    };

    await auditLog(userId, 'DATA_EXPORT', { format: 'JSON', size: JSON.stringify(exportData).length });

    res.json(exportData);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Dashboard stats
app.get('/api/stats', async (req, res) => {
  try {
    const totalUsers = await pool.query('SELECT COUNT(*) FROM users WHERE is_deleted = FALSE');
    const deletionRequests = await pool.query('SELECT COUNT(*) FROM deletion_queue WHERE status = \'completed\'');
    const activeConsents = await pool.query('SELECT COUNT(*) FROM consent_events WHERE status = \'granted\'');
    const auditEntries = await pool.query('SELECT COUNT(*) FROM audit_log');
    const pendingRetention = await pool.query('SELECT COUNT(*) FROM user_analytics WHERE retention_until < NOW()');

    res.json({
      totalUsers: parseInt(totalUsers.rows[0].count),
      deletionRequests: parseInt(deletionRequests.rows[0].count),
      activeConsents: parseInt(activeConsents.rows[0].count),
      auditEntries: parseInt(auditEntries.rows[0].count),
      pendingRetention: parseInt(pendingRetention.rows[0].count)
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Recent audit logs
app.get('/api/audit-logs', async (req, res) => {
  try {
    const logs = await pool.query(
      'SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT 50'
    );
    res.json(logs.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Deletion queue status
app.get('/api/deletion-queue', async (req, res) => {
  try {
    const queue = await pool.query(
      'SELECT * FROM deletion_queue ORDER BY started_at DESC LIMIT 20'
    );
    res.json(queue.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

initDB().then(() => {
  server.listen(3001, () => {
    console.log('✅ GDPR Backend running on port 3001');
  });
});
