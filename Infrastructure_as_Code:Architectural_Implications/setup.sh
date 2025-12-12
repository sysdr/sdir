#!/bin/bash

set -e

# Save original directory
ORIGINAL_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "Infrastructure as Code Demo Setup"
echo "================================================"

# Create project structure
mkdir -p iac-demo/{backend,frontend,infrastructure,tests}
IAC_DEMO_DIR="${SCRIPT_DIR}/iac-demo"
cd "$IAC_DEMO_DIR"

# Create backend package.json
cat > backend/package.json << 'EOF'
{
  "name": "iac-backend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "cors": "^2.8.5",
    "sqlite3": "^5.1.6"
  }
}
EOF

# Create backend server
cat > backend/server.js << 'EOF'
import express from 'express';
import { WebSocketServer } from 'ws';
import cors from 'cors';
import { createServer } from 'http';
import sqlite3 from 'sqlite3';
import { promisify } from 'util';

const app = express();
app.use(cors());
app.use(express.json());

const server = createServer(app);
const wss = new WebSocketServer({ server });

// Initialize SQLite database for state
const db = new sqlite3.Database(':memory:');
const dbRun = promisify(db.run.bind(db));
const dbAll = promisify(db.all.bind(db));

// Initialize database
await dbRun(`
  CREATE TABLE infrastructure_state (
    id INTEGER PRIMARY KEY,
    resource_type TEXT,
    resource_name TEXT,
    status TEXT,
    config TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

await dbRun(`
  CREATE TABLE state_locks (
    lock_id TEXT PRIMARY KEY,
    operation TEXT,
    locked_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

await dbRun(`
  CREATE TABLE deployments (
    id INTEGER PRIMARY KEY,
    operation TEXT,
    resources_affected INTEGER,
    status TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

await dbRun(`
  CREATE TABLE drift_events (
    id INTEGER PRIMARY KEY,
    resource_name TEXT,
    drift_type TEXT,
    detected_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

// Broadcast to all WebSocket clients
function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

// Get current state
app.get('/api/state', async (req, res) => {
  const resources = await dbAll('SELECT * FROM infrastructure_state ORDER BY id');
  const locks = await dbAll('SELECT * FROM state_locks');
  res.json({ resources, locks, locked: locks.length > 0 });
});

// Acquire state lock
app.post('/api/lock', async (req, res) => {
  const { operation } = req.body;
  
  const existingLocks = await dbAll('SELECT * FROM state_locks');
  if (existingLocks.length > 0) {
    return res.status(423).json({ error: 'State is locked', lock: existingLocks[0] });
  }
  
  const lockId = `lock-${Date.now()}`;
  await dbRun('INSERT INTO state_locks (lock_id, operation) VALUES (?, ?)', [lockId, operation]);
  
  broadcast({ type: 'lock_acquired', lockId, operation });
  res.json({ lockId, operation });
});

// Release state lock
app.post('/api/unlock', async (req, res) => {
  const { lockId } = req.body;
  await dbRun('DELETE FROM state_locks WHERE lock_id = ?', [lockId]);
  broadcast({ type: 'lock_released', lockId });
  res.json({ success: true });
});

// Plan infrastructure changes
app.post('/api/plan', async (req, res) => {
  const { resources } = req.body;
  const currentResources = await dbAll('SELECT * FROM infrastructure_state');
  
  const changes = {
    create: [],
    update: [],
    delete: []
  };
  
  const currentMap = new Map(currentResources.map(r => [r.resource_name, r]));
  const desiredMap = new Map(resources.map(r => [r.resource_name, r]));
  
  // Find creates and updates
  for (const [name, desired] of desiredMap) {
    if (!currentMap.has(name)) {
      changes.create.push(desired);
    } else {
      const current = currentMap.get(name);
      if (JSON.stringify(current.config) !== JSON.stringify(desired.config)) {
        changes.update.push(desired);
      }
    }
  }
  
  // Find deletes
  for (const [name] of currentMap) {
    if (!desiredMap.has(name)) {
      changes.delete.push(name);
    }
  }
  
  broadcast({ type: 'plan_generated', changes });
  res.json({ changes });
});

// Apply infrastructure changes
app.post('/api/apply', async (req, res) => {
  const { resources } = req.body;
  let resourcesAffected = 0;
  
  const currentResources = await dbAll('SELECT * FROM infrastructure_state');
  const currentMap = new Map(currentResources.map(r => [r.resource_name, r]));
  
  // Apply creates and updates
  for (const resource of resources) {
    if (!currentMap.has(resource.resource_name)) {
      await dbRun(
        'INSERT INTO infrastructure_state (resource_type, resource_name, status, config) VALUES (?, ?, ?, ?)',
        [resource.resource_type, resource.resource_name, 'active', JSON.stringify(resource.config)]
      );
      resourcesAffected++;
      broadcast({ 
        type: 'resource_created', 
        resource: { ...resource, status: 'active' }
      });
    } else {
      await dbRun(
        'UPDATE infrastructure_state SET config = ?, updated_at = CURRENT_TIMESTAMP WHERE resource_name = ?',
        [JSON.stringify(resource.config), resource.resource_name]
      );
      resourcesAffected++;
      broadcast({ 
        type: 'resource_updated', 
        resource: { ...resource, status: 'active' }
      });
    }
  }
  
  // Record deployment
  await dbRun(
    'INSERT INTO deployments (operation, resources_affected, status) VALUES (?, ?, ?)',
    ['apply', resourcesAffected, 'success']
  );
  
  res.json({ success: true, resourcesAffected });
});

// Destroy resource (simulate manual change/drift)
app.post('/api/drift/manual-change', async (req, res) => {
  const { resourceName, change } = req.body;
  
  await dbRun(
    'UPDATE infrastructure_state SET status = ? WHERE resource_name = ?',
    ['modified', resourceName]
  );
  
  await dbRun(
    'INSERT INTO drift_events (resource_name, drift_type) VALUES (?, ?)',
    [resourceName, change]
  );
  
  broadcast({ 
    type: 'drift_detected', 
    resource: resourceName,
    driftType: change
  });
  
  res.json({ success: true });
});

// Detect drift
app.get('/api/drift/check', async (req, res) => {
  const resources = await dbAll('SELECT * FROM infrastructure_state WHERE status = "modified"');
  const drifts = await dbAll('SELECT * FROM drift_events ORDER BY detected_at DESC LIMIT 10');
  
  res.json({ 
    driftDetected: resources.length > 0,
    driftedResources: resources,
    recentDrifts: drifts
  });
});

// Get deployment history
app.get('/api/deployments', async (req, res) => {
  const deployments = await dbAll('SELECT * FROM deployments ORDER BY timestamp DESC LIMIT 20');
  res.json(deployments);
});

// Get metrics
app.get('/api/metrics', async (req, res) => {
  const resourceCount = await dbAll('SELECT COUNT(*) as count FROM infrastructure_state');
  const deploymentCount = await dbAll('SELECT COUNT(*) as count FROM deployments');
  const driftCount = await dbAll('SELECT COUNT(*) as count FROM drift_events');
  const activeLocks = await dbAll('SELECT COUNT(*) as count FROM state_locks');
  
  res.json({
    totalResources: resourceCount[0].count,
    totalDeployments: deploymentCount[0].count,
    totalDrifts: driftCount[0].count,
    stateLocked: activeLocks[0].count > 0
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

const PORT = 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`IaC Backend running on port ${PORT}`);
});
EOF

# Create frontend package.json
cat > frontend/package.json << 'EOF'
{
  "name": "iac-frontend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.8"
  }
}
EOF

# Create Vite config
cat > frontend/vite.config.js << 'EOF'
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

# Create index.html
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Infrastructure as Code - Dashboard</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

# Create frontend structure
mkdir -p frontend/src

# Create main.jsx
cat > frontend/src/main.jsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

# Create CSS
cat > frontend/src/index.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

#root {
  width: 100%;
  min-height: 100vh;
}
EOF

# Create App component
cat > frontend/src/App.jsx << 'EOF'
import React, { useState, useEffect } from 'react';

const API_URL = 'http://localhost:3001';

export default function App() {
  const [state, setState] = useState({ resources: [], locked: false });
  const [metrics, setMetrics] = useState({});
  const [deployments, setDeployments] = useState([]);
  const [drift, setDrift] = useState({ driftDetected: false, driftedResources: [] });
  const [logs, setLogs] = useState([]);
  const [ws, setWs] = useState(null);

  useEffect(() => {
    fetchState();
    fetchMetrics();
    fetchDeployments();
    checkDrift();

    const websocket = new WebSocket('ws://localhost:3001');
    websocket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      addLog(data.type, JSON.stringify(data));
      
      if (data.type.includes('resource') || data.type.includes('lock')) {
        fetchState();
        fetchMetrics();
      }
      if (data.type === 'drift_detected') {
        checkDrift();
      }
    };
    setWs(websocket);

    const interval = setInterval(() => {
      checkDrift();
      fetchMetrics();
    }, 10000);

    return () => {
      websocket.close();
      clearInterval(interval);
    };
  }, []);

  const addLog = (type, message) => {
    setLogs(prev => [{
      time: new Date().toLocaleTimeString(),
      type,
      message
    }, ...prev].slice(0, 50));
  };

  const fetchState = async () => {
    const res = await fetch(`${API_URL}/api/state`);
    const data = await res.json();
    setState(data);
  };

  const fetchMetrics = async () => {
    const res = await fetch(`${API_URL}/api/metrics`);
    const data = await res.json();
    setMetrics(data);
  };

  const fetchDeployments = async () => {
    const res = await fetch(`${API_URL}/api/deployments`);
    const data = await res.json();
    setDeployments(data);
  };

  const checkDrift = async () => {
    const res = await fetch(`${API_URL}/api/drift/check`);
    const data = await res.json();
    setDrift(data);
  };

  const applyInfrastructure = async () => {
    const sampleResources = [
      {
        resource_type: 'compute',
        resource_name: 'web-server-01',
        config: { instance_type: 't3.medium', region: 'us-east-1' }
      },
      {
        resource_type: 'database',
        resource_name: 'postgres-db',
        config: { engine: 'postgresql', version: '14.5' }
      },
      {
        resource_type: 'storage',
        resource_name: 'backup-bucket',
        config: { storage_class: 'STANDARD', versioning: true }
      }
    ];

    try {
      const lockRes = await fetch(`${API_URL}/api/lock`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ operation: 'apply' })
      });
      
      if (!lockRes.ok) {
        addLog('error', 'Failed to acquire lock');
        return;
      }

      const lock = await lockRes.json();
      addLog('lock_acquired', `Lock: ${lock.lockId}`);

      await fetch(`${API_URL}/api/apply`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ resources: sampleResources })
      });

      await fetch(`${API_URL}/api/unlock`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ lockId: lock.lockId })
      });

      fetchDeployments();
      addLog('apply_success', 'Infrastructure applied successfully');
    } catch (error) {
      addLog('error', error.message);
    }
  };

  const simulateDrift = async () => {
    if (state.resources.length === 0) {
      addLog('error', 'No resources to modify');
      return;
    }

    const resource = state.resources[0];
    await fetch(`${API_URL}/api/drift/manual-change`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        resourceName: resource.resource_name,
        change: 'manual_configuration_change'
      })
    });

    addLog('drift_simulated', `Manual change to ${resource.resource_name}`);
  };

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.title}>Infrastructure as Code Dashboard</h1>
        <div style={styles.statusBadge}>
          <div style={{...styles.statusDot, background: state.locked ? '#ef4444' : '#10b981'}} />
          <span>State {state.locked ? 'Locked' : 'Unlocked'}</span>
        </div>
      </header>

      <div style={styles.metricsGrid}>
        <div style={styles.metricCard}>
          <div style={styles.metricValue}>{metrics.totalResources || 0}</div>
          <div style={styles.metricLabel}>Resources</div>
        </div>
        <div style={styles.metricCard}>
          <div style={styles.metricValue}>{metrics.totalDeployments || 0}</div>
          <div style={styles.metricLabel}>Deployments</div>
        </div>
        <div style={styles.metricCard}>
          <div style={{...styles.metricValue, color: drift.driftDetected ? '#ef4444' : '#10b981'}}>
            {metrics.totalDrifts || 0}
          </div>
          <div style={styles.metricLabel}>Drift Events</div>
        </div>
        <div style={styles.metricCard}>
          <div style={{...styles.metricValue, color: state.locked ? '#ef4444' : '#64748b'}}>
            {state.locks?.length || 0}
          </div>
          <div style={styles.metricLabel}>Active Locks</div>
        </div>
      </div>

      <div style={styles.actionsBar}>
        <button onClick={applyInfrastructure} style={styles.button}>
          Apply Infrastructure
        </button>
        <button onClick={simulateDrift} style={{...styles.button, background: '#f59e0b'}}>
          Simulate Drift
        </button>
        <button onClick={checkDrift} style={{...styles.button, background: '#8b5cf6'}}>
          Check Drift
        </button>
      </div>

      <div style={styles.mainGrid}>
        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>Infrastructure Resources</h2>
          <div style={styles.resourceList}>
            {state.resources.length === 0 ? (
              <div style={styles.emptyState}>No resources deployed</div>
            ) : (
              state.resources.map(resource => (
                <div key={resource.id} style={styles.resourceCard}>
                  <div style={styles.resourceHeader}>
                    <span style={styles.resourceType}>{resource.resource_type}</span>
                    <span style={{
                      ...styles.statusLabel,
                      background: resource.status === 'active' ? '#dcfce7' : '#fee2e2',
                      color: resource.status === 'active' ? '#166534' : '#991b1b'
                    }}>
                      {resource.status}
                    </span>
                  </div>
                  <div style={styles.resourceName}>{resource.resource_name}</div>
                  <div style={styles.resourceConfig}>
                    {JSON.stringify(JSON.parse(resource.config), null, 2)}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>Deployment History</h2>
          <div style={styles.deploymentList}>
            {deployments.map(dep => (
              <div key={dep.id} style={styles.deploymentItem}>
                <div style={styles.deploymentOp}>{dep.operation}</div>
                <div style={styles.deploymentMeta}>
                  {dep.resources_affected} resources • {new Date(dep.timestamp).toLocaleString()}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>
            Drift Detection
            {drift.driftDetected && <span style={styles.alertBadge}>!</span>}
          </h2>
          <div style={styles.driftContent}>
            {drift.driftDetected ? (
              <>
                <div style={styles.driftAlert}>
                  Drift detected in {drift.driftedResources.length} resource(s)
                </div>
                {drift.driftedResources.map(resource => (
                  <div key={resource.id} style={styles.driftItem}>
                    {resource.resource_name} - {resource.status}
                  </div>
                ))}
              </>
            ) : (
              <div style={styles.noDrift}>No drift detected</div>
            )}
          </div>
        </div>

        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>Activity Logs</h2>
          <div style={styles.logsList}>
            {logs.map((log, idx) => (
              <div key={idx} style={styles.logItem}>
                <span style={styles.logTime}>{log.time}</span>
                <span style={styles.logType}>{log.type}</span>
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
    minHeight: '100vh',
    background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    padding: '20px',
  },
  header: {
    background: 'white',
    borderRadius: '12px',
    padding: '30px',
    marginBottom: '20px',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  title: {
    fontSize: '28px',
    fontWeight: 'bold',
    color: '#1e293b',
  },
  statusBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '8px 16px',
    background: '#f1f5f9',
    borderRadius: '20px',
    fontSize: '14px',
    fontWeight: '500',
  },
  statusDot: {
    width: '10px',
    height: '10px',
    borderRadius: '50%',
  },
  metricsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: '20px',
    marginBottom: '20px',
  },
  metricCard: {
    background: 'white',
    borderRadius: '12px',
    padding: '24px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  metricValue: {
    fontSize: '36px',
    fontWeight: 'bold',
    color: '#3b82f6',
    marginBottom: '8px',
  },
  metricLabel: {
    fontSize: '14px',
    color: '#64748b',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  actionsBar: {
    display: 'flex',
    gap: '12px',
    marginBottom: '20px',
    flexWrap: 'wrap',
  },
  button: {
    padding: '12px 24px',
    background: '#3b82f6',
    color: 'white',
    border: 'none',
    borderRadius: '8px',
    fontSize: '14px',
    fontWeight: '600',
    cursor: 'pointer',
    transition: 'all 0.2s',
  },
  mainGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))',
    gap: '20px',
  },
  section: {
    background: 'white',
    borderRadius: '12px',
    padding: '24px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  sectionTitle: {
    fontSize: '18px',
    fontWeight: 'bold',
    color: '#1e293b',
    marginBottom: '16px',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  alertBadge: {
    background: '#ef4444',
    color: 'white',
    width: '20px',
    height: '20px',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '12px',
    fontWeight: 'bold',
  },
  resourceList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  resourceCard: {
    border: '1px solid #e2e8f0',
    borderRadius: '8px',
    padding: '16px',
    background: '#f8fafc',
  },
  resourceHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px',
  },
  resourceType: {
    fontSize: '12px',
    color: '#64748b',
    textTransform: 'uppercase',
    fontWeight: '600',
  },
  statusLabel: {
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '11px',
    fontWeight: '600',
  },
  resourceName: {
    fontSize: '16px',
    fontWeight: '600',
    color: '#1e293b',
    marginBottom: '8px',
  },
  resourceConfig: {
    fontSize: '12px',
    color: '#64748b',
    background: 'white',
    padding: '8px',
    borderRadius: '4px',
    fontFamily: 'monospace',
    whiteSpace: 'pre',
  },
  emptyState: {
    textAlign: 'center',
    padding: '40px',
    color: '#94a3b8',
    fontSize: '14px',
  },
  deploymentList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    maxHeight: '300px',
    overflowY: 'auto',
  },
  deploymentItem: {
    padding: '12px',
    background: '#f8fafc',
    borderRadius: '6px',
    border: '1px solid #e2e8f0',
  },
  deploymentOp: {
    fontSize: '14px',
    fontWeight: '600',
    color: '#1e293b',
    marginBottom: '4px',
  },
  deploymentMeta: {
    fontSize: '12px',
    color: '#64748b',
  },
  driftContent: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  driftAlert: {
    padding: '12px',
    background: '#fee2e2',
    color: '#991b1b',
    borderRadius: '6px',
    fontSize: '14px',
    fontWeight: '500',
  },
  driftItem: {
    padding: '10px',
    background: '#fef3c7',
    borderRadius: '6px',
    fontSize: '13px',
    color: '#92400e',
  },
  noDrift: {
    padding: '20px',
    textAlign: 'center',
    color: '#10b981',
    fontSize: '14px',
    fontWeight: '500',
  },
  logsList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
    maxHeight: '300px',
    overflowY: 'auto',
  },
  logItem: {
    padding: '8px 12px',
    background: '#f8fafc',
    borderRadius: '4px',
    fontSize: '12px',
    display: 'flex',
    gap: '12px',
  },
  logTime: {
    color: '#64748b',
    fontFamily: 'monospace',
  },
  logType: {
    color: '#3b82f6',
    fontWeight: '500',
  },
};
EOF

# Create infrastructure test file
cat > infrastructure/example.tf << 'EOF'
# Example Terraform Configuration

resource "aws_instance" "web_server" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"
  
  tags = {
    Name = "web-server-01"
    Environment = "production"
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "postgres-db"
  engine         = "postgresql"
  engine_version = "14.5"
  instance_class = "db.t3.medium"
}

resource "aws_s3_bucket" "backup" {
  bucket = "backup-bucket"
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    enabled = true
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}
EOF

# Create test script
cat > tests/test_infrastructure.sh << 'EOF'
#!/bin/bash

echo "Running Infrastructure Tests..."
echo "==============================="

# Test 1: State Lock Mechanism
echo "Test 1: State Lock Mechanism"
LOCK_RESPONSE=$(curl -s -X POST http://localhost:3001/api/lock \
  -H "Content-Type: application/json" \
  -d '{"operation":"test"}')

if echo "$LOCK_RESPONSE" | grep -q "lockId"; then
  echo "✓ Lock acquired successfully"
  LOCK_ID=$(echo "$LOCK_RESPONSE" | grep -o '"lockId":"[^"]*"' | cut -d'"' -f4)
  
  # Try to acquire lock again (should fail)
  LOCK_FAIL=$(curl -s -X POST http://localhost:3001/api/lock \
    -H "Content-Type: application/json" \
    -d '{"operation":"test2"}')
  
  if echo "$LOCK_FAIL" | grep -q "locked"; then
    echo "✓ Concurrent lock prevention works"
  else
    echo "✗ Concurrent lock prevention failed"
  fi
  
  # Release lock
  curl -s -X POST http://localhost:3001/api/unlock \
    -H "Content-Type: application/json" \
    -d "{\"lockId\":\"$LOCK_ID\"}" > /dev/null
  echo "✓ Lock released successfully"
else
  echo "✗ Lock acquisition failed"
fi

# Test 2: Infrastructure State Management
echo ""
echo "Test 2: Infrastructure State Management"
STATE=$(curl -s http://localhost:3001/api/state)
if [ ! -z "$STATE" ]; then
  echo "✓ State retrieval successful"
else
  echo "✗ State retrieval failed"
fi

# Test 3: Drift Detection
echo ""
echo "Test 3: Drift Detection"
DRIFT=$(curl -s http://localhost:3001/api/drift/check)
if echo "$DRIFT" | grep -q "driftDetected"; then
  echo "✓ Drift detection operational"
else
  echo "✗ Drift detection failed"
fi

# Test 4: Metrics Collection
echo ""
echo "Test 4: Metrics Collection"
METRICS=$(curl -s http://localhost:3001/api/metrics)
if echo "$METRICS" | grep -q "totalResources"; then
  echo "✓ Metrics collection working"
else
  echo "✗ Metrics collection failed"
fi

echo ""
echo "==============================="
echo "All tests completed!"
EOF

chmod +x tests/test_infrastructure.sh

# Create Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3001/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    depends_on:
      - backend
    environment:
      - NODE_ENV=production

networks:
  default:
    name: iac-network
EOF

# Create backend Dockerfile
cat > backend/Dockerfile << 'EOF'
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

EXPOSE 3001

CMD ["npm", "start"]
EOF

# Create frontend Dockerfile
cat > frontend/Dockerfile << 'EOF'
FROM node:20-alpine as builder

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

FROM node:20-alpine

WORKDIR /app

RUN npm install -g serve

COPY --from=builder /app/dist ./dist

EXPOSE 3000

CMD ["serve", "-s", "dist", "-l", "3000"]
EOF

echo ""
echo "Checking for existing services..."
# Ensure we're in the iac-demo directory
cd "$IAC_DEMO_DIR"
if [ ! -f "docker-compose.yml" ]; then
  echo "Error: docker-compose.yml not found in $IAC_DEMO_DIR"
  exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
  echo "Warning: Docker not found. Skipping Docker setup."
  echo "You can start services manually using the startup scripts."
else
  # Check for running containers
  if command -v docker-compose &> /dev/null; then
    if docker-compose ps 2>/dev/null | grep -q "Up"; then
      echo "Stopping existing services..."
      docker-compose down
    fi
    
    echo "Building Docker containers..."
    docker-compose build || echo "Warning: Docker build failed"
    
    echo ""
    echo "Starting services..."
    docker-compose up -d || echo "Warning: Failed to start services"
    
    echo ""
    echo "Waiting for services to be ready..."
    sleep 10
    
    echo ""
    echo "Running tests..."
    if [ -f "tests/test_infrastructure.sh" ]; then
      cd tests
      ./test_infrastructure.sh
      cd ..
    else
      echo "Warning: test_infrastructure.sh not found"
    fi
  elif command -v docker &> /dev/null; then
    echo "docker-compose not found, but docker is available"
    echo "Please install docker-compose or use the startup scripts instead"
  fi
fi
cd "$SCRIPT_DIR"

echo ""
echo "================================================"
echo "Infrastructure as Code Demo is Ready!"
echo "================================================"
echo ""
echo "Access the dashboard at: http://localhost:3000"
echo ""
echo "Try these actions in the dashboard:"
echo "1. Click 'Apply Infrastructure' to deploy resources"
echo "2. Watch the state lock mechanism in action"
echo "3. Click 'Simulate Drift' to trigger manual changes"
echo "4. Observe drift detection (runs every 10 seconds)"
echo "5. View deployment history and activity logs"
echo ""
echo "Backend API available at: http://localhost:3001"
echo ""
echo "Key Features Demonstrated:"
echo "- State management with locking"
echo "- Drift detection and alerting"
echo "- Resource lifecycle management"
echo "- Deployment history tracking"
echo "- Real-time activity monitoring"
echo ""
cd "$SCRIPT_DIR"
EOF

# Create demo.sh script
cat > "${SCRIPT_DIR}/demo.sh" << 'EOF'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DEMO_DIR="${SCRIPT_DIR}/iac-demo"

if [ ! -d "$IAC_DEMO_DIR" ]; then
  echo "Error: iac-demo directory not found. Please run setup.sh first."
  exit 1
fi

cd "$IAC_DEMO_DIR"

echo "Starting Infrastructure as Code Demo..."
echo "========================================"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
  echo "Error: docker-compose not found"
  exit 1
fi

# Check for running containers
if docker-compose ps | grep -q "Up"; then
  echo "Services are already running. Stopping existing services..."
  docker-compose down
fi

echo "Building containers..."
docker-compose build

echo "Starting services..."
docker-compose up -d

echo "Waiting for services to be ready..."
sleep 15

# Check health
echo "Checking service health..."
BACKEND_HEALTH=$(curl -s http://localhost:3001/health || echo "failed")
if echo "$BACKEND_HEALTH" | grep -q "healthy"; then
  echo "✓ Backend is healthy"
else
  echo "✗ Backend health check failed"
fi

echo ""
echo "========================================"
echo "Demo is ready!"
echo "========================================"
echo "Dashboard: http://localhost:3000"
echo "Backend API: http://localhost:3001"
echo ""
echo "To stop services, run: cd iac-demo && docker-compose down"
EOF

chmod +x "${SCRIPT_DIR}/demo.sh"

# Create cleanup script
cat > "${SCRIPT_DIR}/cleanup.sh" << 'EOF'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DEMO_DIR="${SCRIPT_DIR}/iac-demo"

echo "Cleaning up Infrastructure as Code Demo..."

if [ ! -d "$IAC_DEMO_DIR" ]; then
  echo "iac-demo directory not found. Nothing to clean up."
  exit 0
fi

cd "$IAC_DEMO_DIR"

echo "Stopping containers..."
docker-compose down -v

echo "Removing Docker images..."
docker-compose rm -f

cd "$SCRIPT_DIR"

echo "Removing project files..."
rm -rf iac-demo

echo "Cleanup complete!"
EOF

chmod +x "${SCRIPT_DIR}/cleanup.sh"

# Create backend startup script
cat > "${IAC_DEMO_DIR}/backend/start.sh" << 'EOF'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/package.json" ]; then
  echo "Error: package.json not found in ${SCRIPT_DIR}"
  exit 1
fi

cd "$SCRIPT_DIR"

if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

echo "Starting backend server..."
npm start
EOF

chmod +x "${IAC_DEMO_DIR}/backend/start.sh"

# Create frontend startup script
cat > "${IAC_DEMO_DIR}/frontend/start.sh" << 'EOF'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/package.json" ]; then
  echo "Error: package.json not found in ${SCRIPT_DIR}"
  exit 1
fi

cd "$SCRIPT_DIR"

if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

echo "Starting frontend development server..."
npm run dev
EOF

chmod +x "${IAC_DEMO_DIR}/frontend/start.sh"

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo ""
echo "Run the demo with:"
echo "  ./demo.sh"
echo ""
echo "Or start services individually:"
echo "  cd iac-demo/backend && ./start.sh"
echo "  cd iac-demo/frontend && ./start.sh"
echo ""
echo "Clean up with:"
echo "  ./cleanup.sh"
echo ""