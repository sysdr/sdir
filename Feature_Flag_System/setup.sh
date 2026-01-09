#!/bin/bash

echo "=== Feature Flag System Setup ==="
echo "Building production-grade feature flag infrastructure..."

# Create directory structure
mkdir -p flag-system/{flag-service,dashboard,services/{checkout,payment,recommendations},tests}
cd flag-system

# ==============================================
# FLAG MANAGEMENT SERVICE
# ==============================================

cat > flag-service/package.json << 'EOF'
{
  "name": "flag-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "pg": "^8.11.3",
    "redis": "^4.6.10",
    "uuid": "^9.0.1",
    "cors": "^2.8.5"
  }
}
EOF

cat > flag-service/server.js << 'EOF'
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
EOF

# ==============================================
# DASHBOARD (React)
# ==============================================

cat > dashboard/package.json << 'EOF'
{
  "name": "dashboard",
  "version": "1.0.0",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.7"
  },
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 8080 --host"
  }
}
EOF

cat > dashboard/vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { host: '0.0.0.0', port: 8080 }
});
EOF

cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Feature Flag System</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

mkdir -p dashboard/src
cat > dashboard/src/main.jsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
EOF

cat > dashboard/src/App.jsx << 'EOF'
import React, { useState, useEffect } from 'react';

const API_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';

export default function App() {
  const [flags, setFlags] = useState([]);
  const [stats, setStats] = useState({});
  const [ws, setWs] = useState(null);
  const [evaluations, setEvaluations] = useState([]);

  useEffect(() => {
    fetchFlags();
    fetchStats();
    
    const socket = new WebSocket(WS_URL);
    socket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'flag_updated') {
        fetchFlags();
      }
    };
    setWs(socket);
    
    const statsInterval = setInterval(fetchStats, 2000);
    
    return () => {
      socket.close();
      clearInterval(statsInterval);
    };
  }, []);

  const fetchFlags = async () => {
    const res = await fetch(`${API_URL}/flags`);
    const data = await res.json();
    setFlags(data);
  };

  const fetchStats = async () => {
    const res = await fetch(`${API_URL}/stats`);
    const data = await res.json();
    setStats(data);
  };

  const toggleFlag = async (id) => {
    await fetch(`${API_URL}/flags/${id}/toggle`, { method: 'POST' });
  };

  const updateRollout = async (id, percentage) => {
    await fetch(`${API_URL}/flags/${id}/rollout`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ percentage })
    });
  };

  const testEvaluation = async (flagId) => {
    const userId = `user-${Math.floor(Math.random() * 1000)}`;
    const context = { segment: 'beta', region: 'US' };
    
    const res = await fetch(`${API_URL}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ flagId, userId, context })
    });
    
    const data = await res.json();
    setEvaluations(prev => [{ ...data, timestamp: new Date() }, ...prev.slice(0, 19)]);
  };

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.title}>🚩 Feature Flag System</h1>
        <div style={styles.statsBar}>
          <div style={styles.stat}>
            <div style={styles.statValue}>{stats.total_flags || 0}</div>
            <div style={styles.statLabel}>Total Flags</div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statValue}>{stats.total_evaluations || 0}</div>
            <div style={styles.statLabel}>Total Evaluations</div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statValue}>
              {stats.recent_evaluations?.reduce((sum, r) => sum + parseInt(r.count), 0) || 0}
            </div>
            <div style={styles.statLabel}>Evals/min</div>
          </div>
        </div>
      </header>

      <div style={styles.content}>
        <div style={styles.flagsSection}>
          <h2 style={styles.sectionTitle}>Feature Flags</h2>
          <div style={styles.flagGrid}>
            {flags.map(flag => (
              <div key={flag.id} style={styles.flagCard}>
                <div style={styles.flagHeader}>
                  <div>
                    <h3 style={styles.flagName}>{flag.name}</h3>
                    <p style={styles.flagDesc}>{flag.description}</p>
                  </div>
                  <button
                    onClick={() => toggleFlag(flag.id)}
                    style={{
                      ...styles.toggleBtn,
                      ...(flag.enabled ? styles.toggleBtnOn : styles.toggleBtnOff)
                    }}
                  >
                    {flag.enabled ? 'ON' : 'OFF'}
                  </button>
                </div>
                
                <div style={styles.rolloutSection}>
                  <div style={styles.rolloutHeader}>
                    <span style={styles.rolloutLabel}>Rollout: {flag.rollout_percentage}%</span>
                    <button
                      onClick={() => testEvaluation(flag.id)}
                      style={styles.testBtn}
                    >
                      Test
                    </button>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="100"
                    value={flag.rollout_percentage}
                    onChange={(e) => updateRollout(flag.id, parseInt(e.target.value))}
                    style={styles.slider}
                  />
                  <div style={styles.progressBar}>
                    <div 
                      style={{
                        ...styles.progressFill,
                        width: `${flag.rollout_percentage}%`
                      }}
                    />
                  </div>
                </div>
                
                {flag.targeting_rules && Object.keys(
                  typeof flag.targeting_rules === 'string' 
                    ? JSON.parse(flag.targeting_rules) 
                    : flag.targeting_rules
                ).length > 0 && (
                  <div style={styles.targeting}>
                    <strong>Targeting:</strong> {JSON.stringify(
                      typeof flag.targeting_rules === 'string' 
                        ? JSON.parse(flag.targeting_rules) 
                        : flag.targeting_rules
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        <div style={styles.evalsSection}>
          <h2 style={styles.sectionTitle}>Recent Evaluations</h2>
          <div style={styles.evalsList}>
            {evaluations.map((eval, i) => (
              <div key={i} style={styles.evalItem}>
                <span style={eval.enabled ? styles.evalEnabled : styles.evalDisabled}>
                  {eval.enabled ? '✓' : '✗'}
                </span>
                <span style={styles.evalFlag}>{eval.flagId}</span>
                <span style={styles.evalUser}>{eval.userId}</span>
                <span style={styles.evalTime}>
                  {eval.timestamp.toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

const styles = {
  container: {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    minHeight: '100vh',
    padding: '20px',
  },
  header: {
    background: 'white',
    borderRadius: '16px',
    padding: '30px',
    marginBottom: '20px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)',
  },
  title: {
    margin: '0 0 20px 0',
    fontSize: '32px',
    color: '#2d3748',
  },
  statsBar: {
    display: 'flex',
    gap: '30px',
  },
  stat: {
    flex: 1,
    textAlign: 'center',
  },
  statValue: {
    fontSize: '36px',
    fontWeight: 'bold',
    color: '#3b82f6',
  },
  statLabel: {
    fontSize: '14px',
    color: '#718096',
    marginTop: '5px',
  },
  content: {
    display: 'grid',
    gridTemplateColumns: '2fr 1fr',
    gap: '20px',
  },
  flagsSection: {
    background: 'white',
    borderRadius: '16px',
    padding: '30px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)',
  },
  sectionTitle: {
    margin: '0 0 20px 0',
    fontSize: '24px',
    color: '#2d3748',
  },
  flagGrid: {
    display: 'grid',
    gap: '15px',
  },
  flagCard: {
    background: '#f7fafc',
    borderRadius: '12px',
    padding: '20px',
    border: '2px solid #e2e8f0',
  },
  flagHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '15px',
  },
  flagName: {
    margin: '0 0 5px 0',
    fontSize: '18px',
    color: '#2d3748',
  },
  flagDesc: {
    margin: 0,
    fontSize: '14px',
    color: '#718096',
  },
  toggleBtn: {
    padding: '8px 20px',
    border: 'none',
    borderRadius: '20px',
    fontSize: '14px',
    fontWeight: 'bold',
    cursor: 'pointer',
    transition: 'all 0.3s',
  },
  toggleBtnOn: {
    background: '#48bb78',
    color: 'white',
  },
  toggleBtnOff: {
    background: '#cbd5e0',
    color: '#4a5568',
  },
  rolloutSection: {
    marginTop: '15px',
  },
  rolloutHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '10px',
  },
  rolloutLabel: {
    fontSize: '14px',
    fontWeight: 'bold',
    color: '#4a5568',
  },
  testBtn: {
    padding: '5px 15px',
    background: '#3b82f6',
    color: 'white',
    border: 'none',
    borderRadius: '6px',
    fontSize: '12px',
    cursor: 'pointer',
  },
  slider: {
    width: '100%',
    marginBottom: '10px',
  },
  progressBar: {
    height: '8px',
    background: '#e2e8f0',
    borderRadius: '4px',
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    background: 'linear-gradient(90deg, #3b82f6, #60a5fa)',
    transition: 'width 0.3s',
  },
  targeting: {
    marginTop: '15px',
    padding: '10px',
    background: '#edf2f7',
    borderRadius: '6px',
    fontSize: '12px',
    color: '#4a5568',
  },
  evalsSection: {
    background: 'white',
    borderRadius: '16px',
    padding: '30px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)',
  },
  evalsList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '10px',
  },
  evalItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    padding: '12px',
    background: '#f7fafc',
    borderRadius: '8px',
    fontSize: '13px',
  },
  evalEnabled: {
    color: '#48bb78',
    fontWeight: 'bold',
    fontSize: '16px',
  },
  evalDisabled: {
    color: '#f56565',
    fontWeight: 'bold',
    fontSize: '16px',
  },
  evalFlag: {
    flex: 1,
    color: '#2d3748',
    fontWeight: '500',
  },
  evalUser: {
    color: '#718096',
    fontSize: '12px',
  },
  evalTime: {
    color: '#a0aec0',
    fontSize: '11px',
  },
};
EOF

# ==============================================
# MICROSERVICES (Checkout, Payment, Recommendations)
# ==============================================

# Checkout Service
cat > services/checkout/package.json << 'EOF'
{
  "name": "checkout-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "node-fetch": "^2.7.0"
  }
}
EOF

cat > services/checkout/server.js << 'EOF'
const express = require('express');
const fetch = require('node-fetch');

const app = express();
const FLAG_SERVICE = 'http://flag-service:3000';

let evaluationCount = 0;

async function evaluateFlag(flagId, userId) {
  try {
    const res = await fetch(`${FLAG_SERVICE}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        flagId, 
        userId, 
        context: { segment: 'premium', region: 'US' }
      })
    });
    evaluationCount++;
    const data = await res.json();
    return data.enabled;
  } catch (error) {
    console.error('Flag evaluation failed:', error.message);
    return false; // Fail closed
  }
}

app.get('/checkout/:userId', async (req, res) => {
  const { userId } = req.params;
  
  const fastCheckoutEnabled = await evaluateFlag('fast-checkout', userId);
  const newPaymentEnabled = await evaluateFlag('new-payment-flow', userId);
  
  res.json({
    service: 'checkout',
    userId,
    flow: fastCheckoutEnabled ? 'one-click' : 'standard',
    paymentVersion: newPaymentEnabled ? 'v2' : 'v1',
    evaluations: evaluationCount
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'checkout' });
});

app.listen(3001, () => console.log('Checkout service on port 3001'));
EOF

# Payment Service
cat > services/payment/package.json << 'EOF'
{
  "name": "payment-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "node-fetch": "^2.7.0"
  }
}
EOF

cat > services/payment/server.js << 'EOF'
const express = require('express');
const fetch = require('node-fetch');

const app = express();
const FLAG_SERVICE = 'http://flag-service:3000';

async function evaluateFlag(flagId, userId) {
  try {
    const res = await fetch(`${FLAG_SERVICE}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ flagId, userId, context: {} })
    });
    const data = await res.json();
    return data.enabled;
  } catch (error) {
    return false;
  }
}

app.get('/process/:userId', async (req, res) => {
  const { userId } = req.params;
  
  const newFlowEnabled = await evaluateFlag('new-payment-flow', userId);
  
  const processingTime = newFlowEnabled ? 200 : 500;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  res.json({
    service: 'payment',
    userId,
    version: newFlowEnabled ? 'streamlined' : 'legacy',
    processingTime: `${processingTime}ms`
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment' });
});

app.listen(3002, () => console.log('Payment service on port 3002'));
EOF

# Recommendations Service
cat > services/recommendations/package.json << 'EOF'
{
  "name": "recommendations-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "node-fetch": "^2.7.0"
  }
}
EOF

cat > services/recommendations/server.js << 'EOF'
const express = require('express');
const fetch = require('node-fetch');

const app = express();
const FLAG_SERVICE = 'http://flag-service:3000';

async function evaluateFlag(flagId, userId) {
  try {
    const res = await fetch(`${FLAG_SERVICE}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        flagId, 
        userId, 
        context: { region: 'US' }
      })
    });
    const data = await res.json();
    return data.enabled;
  } catch (error) {
    return false;
  }
}

app.get('/recommendations/:userId', async (req, res) => {
  const { userId } = req.params;
  
  const v2Enabled = await evaluateFlag('recommendations-v2', userId);
  
  const recommendations = v2Enabled 
    ? ['ML-Powered Item A', 'ML-Powered Item B', 'ML-Powered Item C']
    : ['Standard Item 1', 'Standard Item 2', 'Standard Item 3'];
  
  res.json({
    service: 'recommendations',
    userId,
    engine: v2Enabled ? 'ml-v2' : 'rule-based',
    items: recommendations
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'recommendations' });
});

app.listen(3003, () => console.log('Recommendations service on port 3003'));
EOF

# ==============================================
# TESTS
# ==============================================

cat > tests/package.json << 'EOF'
{
  "name": "tests",
  "version": "1.0.0",
  "dependencies": {
    "node-fetch": "^2.7.0"
  }
}
EOF

cat > tests/run-tests.js << 'EOF'
const fetch = require('node-fetch');

const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  reset: '\x1b[0m'
};

async function test(name, fn) {
  try {
    await fn();
    console.log(`${colors.green}✓${colors.reset} ${name}`);
    return true;
  } catch (error) {
    console.log(`${colors.red}✗${colors.reset} ${name}`);
    console.log(`  Error: ${error.message}`);
    return false;
  }
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('\n=== Feature Flag System Tests ===\n');
  
  const results = [];
  
  // Wait for services
  console.log('Waiting for services to be ready...');
  await sleep(5000);
  
  // Test flag service health
  results.push(await test('Flag service is healthy', async () => {
    const res = await fetch('http://flag-service:3000/health');
    const data = await res.json();
    if (data.status !== 'healthy') throw new Error('Service unhealthy');
  }));
  
  // Test retrieve all flags
  results.push(await test('Retrieve all flags', async () => {
    const res = await fetch('http://flag-service:3000/flags');
    const flags = await res.json();
    if (!Array.isArray(flags)) throw new Error('Expected array');
    if (flags.length === 0) throw new Error('No flags found');
  }));
  
  // Test flag evaluation
  results.push(await test('Evaluate flag for user', async () => {
    const res = await fetch('http://flag-service:3000/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        flagId: 'fast-checkout',
        userId: 'test-user-123',
        context: {}
      })
    });
    const data = await res.json();
    if (typeof data.enabled !== 'boolean') throw new Error('Invalid response');
  }));
  
  // Test consistent hashing
  results.push(await test('Consistent user assignment', async () => {
    const userId = 'consistency-test-user';
    const results = [];
    
    for (let i = 0; i < 5; i++) {
      const res = await fetch('http://flag-service:3000/evaluate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          flagId: 'new-payment-flow',
          userId,
          context: {}
        })
      });
      const data = await res.json();
      results.push(data.enabled);
    }
    
    const allSame = results.every(r => r === results[0]);
    if (!allSame) throw new Error('Inconsistent assignment');
  }));
  
  // Test toggle flag
  results.push(await test('Toggle flag', async () => {
    const res = await fetch('http://flag-service:3000/flags/dark-mode/toggle', {
      method: 'POST'
    });
    const flag = await res.json();
    if (!flag.id) throw new Error('Toggle failed');
  }));
  
  // Test rollout percentage
  results.push(await test('Update rollout percentage', async () => {
    const res = await fetch('http://flag-service:3000/flags/new-payment-flow/rollout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ percentage: 75 })
    });
    const flag = await res.json();
    if (flag.rollout_percentage !== 75) throw new Error('Rollout update failed');
  }));
  
  // Test checkout service
  results.push(await test('Checkout service responds correctly', async () => {
    const res = await fetch('http://checkout-service:3001/checkout/test-user');
    const data = await res.json();
    if (!data.flow) throw new Error('Invalid checkout response');
  }));
  
  // Test payment service
  results.push(await test('Payment service responds correctly', async () => {
    const res = await fetch('http://payment-service:3002/process/test-user');
    const data = await res.json();
    if (!data.version) throw new Error('Invalid payment response');
  }));
  
  // Test recommendations service
  results.push(await test('Recommendations service responds correctly', async () => {
    const res = await fetch('http://recommendations-service:3003/recommendations/test-user');
    const data = await res.json();
    if (!data.items) throw new Error('Invalid recommendations response');
  }));
  
  // Test statistics endpoint
  results.push(await test('Statistics endpoint works', async () => {
    const res = await fetch('http://flag-service:3000/stats');
    const stats = await res.json();
    if (typeof stats.total_flags !== 'number') throw new Error('Invalid stats');
  }));
  
  const passed = results.filter(r => r).length;
  const total = results.length;
  
  console.log(`\n=== Results: ${passed}/${total} tests passed ===\n`);
  
  if (passed !== total) {
    process.exit(1);
  }
}

runTests().catch(console.error);
EOF

# ==============================================
# DOCKER SETUP
# ==============================================

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: flags
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  flag-service:
    build:
      context: ./flag-service
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      POSTGRES_HOST: postgres
      REDIS_HOST: redis
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  checkout-service:
    build:
      context: ./services/checkout
      dockerfile: Dockerfile
    depends_on:
      - flag-service

  payment-service:
    build:
      context: ./services/payment
      dockerfile: Dockerfile
    depends_on:
      - flag-service

  recommendations-service:
    build:
      context: ./services/recommendations
      dockerfile: Dockerfile
    depends_on:
      - flag-service

  dashboard:
    build:
      context: ./dashboard
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    depends_on:
      - flag-service

  tests:
    build:
      context: ./tests
      dockerfile: Dockerfile
    depends_on:
      - flag-service
      - checkout-service
      - payment-service
      - recommendations-service

volumes:
  postgres_data:
EOF

# Dockerfiles
cat > flag-service/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

cat > services/checkout/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

cat > services/payment/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

cat > services/recommendations/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
RUN npm run build
CMD ["npm", "run", "preview"]
EOF

cat > tests/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "run-tests.js"]
EOF

# ==============================================
# HELPER SCRIPTS
# ==============================================

cat > demo.sh << 'EOF'
#!/bin/bash
echo "=== Feature Flag System Demo ==="
echo ""
echo "Dashboard: http://localhost:8080"
echo ""
echo "Try these commands:"
echo ""
echo "# Check flag service stats"
echo "curl http://localhost:3000/stats"
echo ""
echo "# Evaluate flag for a user"
echo "curl -X POST http://localhost:3000/evaluate \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"flagId\":\"new-payment-flow\",\"userId\":\"user-123\",\"context\":{}}'"
echo ""
echo "# Test checkout service"
echo "curl http://localhost:3001/checkout/user-456"
echo ""
echo "# Test payment service"
echo "curl http://localhost:3002/process/user-789"
echo ""
echo "# Test recommendations service"
echo "curl http://localhost:3003/recommendations/user-101"
echo ""
echo "Services are running. Press Ctrl+C to stop."
docker-compose logs -f
EOF

cat > cleanup.sh << 'EOF'
#!/bin/bash
echo "Cleaning up Feature Flag System..."
docker-compose down -v
echo "✓ Cleanup complete"
EOF

chmod +x demo.sh cleanup.sh

# ==============================================
# BUILD AND RUN
# ==============================================

echo ""
echo "Building Docker containers..."
docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d postgres redis flag-service checkout-service payment-service recommendations-service dashboard

echo ""
echo "Waiting for services to be ready..."
sleep 10

echo ""
echo "Running tests..."
docker-compose run --rm tests

echo ""
echo "=== Setup Complete ==="
echo ""
echo "🎯 Dashboard: http://localhost:8080"
echo "🚩 Flag Service: http://localhost:3000"
echo ""
echo "Run './demo.sh' for demo instructions"
echo "Run './cleanup.sh' to stop and remove everything"
echo ""