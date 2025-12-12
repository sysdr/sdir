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
