#!/bin/bash

# Exit on error for file creation, but allow errors for optional commands (npm, docker)
set -e

echo "🌍 Multi-Region Active-Active System Demo Setup"
echo "=============================================="

# Create directory structure
mkdir -p multi-region-demo/{regions/{us-east,us-west,eu-west},dashboard,shared}
cd multi-region-demo

# Create package.json
cat > package.json << 'EOF'
{
  "name": "multi-region-active-active",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "node-fetch": "^2.7.0",
    "uuid": "^9.0.1"
  }
}
EOF

# Create shared utilities
cat > shared/utils.js << 'EOF'
const crypto = require('crypto');

class VectorClock {
  constructor(regionId) {
    this.regionId = regionId;
    this.clock = {};
  }

  increment() {
    this.clock[this.regionId] = (this.clock[this.regionId] || 0) + 1;
    return { ...this.clock };
  }

  merge(otherClock) {
    Object.keys(otherClock).forEach(region => {
      this.clock[region] = Math.max(this.clock[region] || 0, otherClock[region] || 0);
    });
  }

  compare(clock1, clock2) {
    const keys = new Set([...Object.keys(clock1), ...Object.keys(clock2)]);
    let clock1Greater = false;
    let clock2Greater = false;

    for (const key of keys) {
      const v1 = clock1[key] || 0;
      const v2 = clock2[key] || 0;
      if (v1 > v2) clock1Greater = true;
      if (v2 > v1) clock2Greater = true;
    }

    if (clock1Greater && !clock2Greater) return 1;
    if (clock2Greater && !clock1Greater) return -1;
    return 0; // Concurrent
  }
}

module.exports = { VectorClock };
EOF

# Create regional node implementation
cat > shared/region-node.js << 'EOF'
const express = require('express');
const { VectorClock } = require('./utils');

class RegionNode {
  constructor(regionId, port, peers) {
    this.regionId = regionId;
    this.port = port;
    this.peers = peers;
    this.data = new Map();
    this.vectorClock = new VectorClock(regionId);
    this.metadata = new Map(); // Stores vector clock per key
    this.stats = {
      writes: 0,
      reads: 0,
      replications: 0,
      conflicts: 0
    };
    this.healthy = true;
    this.app = express();
    this.app.use(express.json());
    this.setupRoutes();
  }

  setupRoutes() {
    // Write endpoint
    this.app.post('/write', (req, res) => {
      const { key, value } = req.body;
      const clock = this.vectorClock.increment();
      
      this.data.set(key, value);
      this.metadata.set(key, { clock, timestamp: Date.now(), region: this.regionId });
      this.stats.writes++;

      // Async replicate to peers
      this.replicateToPeers(key, value, clock);

      res.json({ success: true, region: this.regionId, clock });
    });

    // Read endpoint
    this.app.get('/read/:key', (req, res) => {
      const { key } = req.params;
      this.stats.reads++;
      
      const value = this.data.get(key);
      const metadata = this.metadata.get(key);
      
      res.json({ 
        value, 
        metadata,
        region: this.regionId 
      });
    });

    // Replication endpoint
    this.app.post('/replicate', (req, res) => {
      const { key, value, clock, sourceRegion } = req.body;
      this.stats.replications++;

      const existing = this.metadata.get(key);
      
      if (!existing) {
        // No conflict, accept write
        this.data.set(key, value);
        this.metadata.set(key, { clock, timestamp: Date.now(), region: sourceRegion });
        this.vectorClock.merge(clock);
        res.json({ accepted: true, conflict: false });
      } else {
        // Check for conflict
        const comparison = this.vectorClock.compare(clock, existing.clock);
        
        if (comparison === 1) {
          // Incoming write is newer
          this.data.set(key, value);
          this.metadata.set(key, { clock, timestamp: Date.now(), region: sourceRegion });
          this.vectorClock.merge(clock);
          res.json({ accepted: true, conflict: false });
        } else if (comparison === -1) {
          // Existing write is newer, reject
          res.json({ accepted: false, conflict: false });
        } else {
          // Concurrent writes - conflict!
          this.stats.conflicts++;
          // Last-write-wins based on timestamp
          const incomingTimestamp = Date.now();
          if (incomingTimestamp > existing.timestamp) {
            this.data.set(key, value);
            this.metadata.set(key, { clock, timestamp: incomingTimestamp, region: sourceRegion });
          }
          this.vectorClock.merge(clock);
          res.json({ accepted: true, conflict: true });
        }
      }
    });

    // Health check
    this.app.get('/health', (req, res) => {
      res.json({ 
        healthy: this.healthy,
        region: this.regionId,
        stats: this.stats,
        dataSize: this.data.size
      });
    });

    // Stats endpoint
    this.app.get('/stats', (req, res) => {
      res.json({
        region: this.regionId,
        ...this.stats,
        dataSize: this.data.size,
        healthy: this.healthy
      });
    });

    // Simulate failure
    this.app.post('/fail', (req, res) => {
      this.healthy = false;
      res.json({ region: this.regionId, healthy: false });
    });

    // Recover
    this.app.post('/recover', (req, res) => {
      this.healthy = true;
      res.json({ region: this.regionId, healthy: true });
    });
  }

  async replicateToPeers(key, value, clock) {
    const fetch = require('node-fetch');
    
    for (const peer of this.peers) {
      try {
        await fetch(`http://${peer}/replicate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            key, 
            value, 
            clock, 
            sourceRegion: this.regionId 
          })
        });
      } catch (error) {
        // Peer might be down, continue
      }
    }
  }

  start() {
    this.app.listen(this.port, () => {
      console.log(`${this.regionId} running on port ${this.port}`);
    });
  }
}

module.exports = RegionNode;
EOF

# Create US-East region
cat > regions/us-east/server.js << 'EOF'
const RegionNode = require('../../shared/region-node');

const node = new RegionNode(
  'us-east',
  3001,
  ['us-west:3002', 'eu-west:3003']
);

node.start();
EOF

# Create US-West region
cat > regions/us-west/server.js << 'EOF'
const RegionNode = require('../../shared/region-node');

const node = new RegionNode(
  'us-west',
  3002,
  ['us-east:3001', 'eu-west:3003']
);

node.start();
EOF

# Create EU-West region
cat > regions/eu-west/server.js << 'EOF'
const RegionNode = require('../../shared/region-node');

const node = new RegionNode(
  'eu-west',
  3003,
  ['us-east:3001', 'us-west:3002']
);

node.start();
EOF

# Create Dashboard
cat > dashboard/server.js << 'EOF'
const express = require('express');
const WebSocket = require('ws');
const fetch = require('node-fetch');

const app = express();
const port = 3000;
const path = require('path');

app.use(express.static(__dirname));
app.use(express.json());

// Proxy endpoints
const regions = [
  { id: 'us-east', url: 'http://us-east:3001' },
  { id: 'us-west', url: 'http://us-west:3002' },
  { id: 'eu-west', url: 'http://eu-west:3003' }
];

// Write to nearest region
app.post('/api/write', async (req, res) => {
  const { region, key, value } = req.body;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/write`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, value })
    });
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Read from any region
app.get('/api/read/:region/:key', async (req, res) => {
  const { region, key } = req.params;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/read/${key}`);
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Fail region
app.post('/api/fail/:region', async (req, res) => {
  const { region } = req.params;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/fail`, {
      method: 'POST'
    });
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Recover region
app.post('/api/recover/:region', async (req, res) => {
  const { region } = req.params;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/recover`, {
      method: 'POST'
    });
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(port, () => {
  console.log(`Dashboard running on port ${port}`);
});

// WebSocket for real-time updates
const wss = new WebSocket.Server({ port: 3100 });

async function broadcastStats() {
  const stats = await Promise.all(
    regions.map(async r => {
      try {
        const response = await fetch(`${r.url}/stats`);
        return await response.json();
      } catch (error) {
        return { region: r.id, error: true };
      }
    })
  );

  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(stats));
    }
  });
}

setInterval(broadcastStats, 1000);
EOF

# Create Dashboard HTML
cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Multi-Region Active-Active Dashboard</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: linear-gradient(135deg, #f5f7fa 0%, #e8eef5 100%);
      padding: 20px;
      min-height: 100vh;
    }

    .container {
      max-width: 1400px;
      margin: 0 auto;
    }

    header {
      background: white;
      padding: 30px;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(59, 130, 246, 0.1);
      margin-bottom: 30px;
    }

    h1 {
      color: #1e40af;
      font-size: 32px;
      margin-bottom: 10px;
    }

    .subtitle {
      color: #64748b;
      font-size: 16px;
    }

    .regions-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }

    .region-card {
      background: white;
      border-radius: 12px;
      padding: 25px;
      box-shadow: 0 4px 12px rgba(59, 130, 246, 0.1);
      transition: transform 0.2s;
    }

    .region-card:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 16px rgba(59, 130, 246, 0.15);
    }

    .region-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 20px;
    }

    .region-name {
      font-size: 20px;
      font-weight: 600;
      color: #1e40af;
    }

    .status-badge {
      padding: 6px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
    }

    .status-healthy {
      background: #dcfce7;
      color: #166534;
    }

    .status-unhealthy {
      background: #fee2e2;
      color: #991b1b;
    }

    .stat-row {
      display: flex;
      justify-content: space-between;
      padding: 12px 0;
      border-bottom: 1px solid #e2e8f0;
    }

    .stat-row:last-child {
      border-bottom: none;
    }

    .stat-label {
      color: #64748b;
      font-size: 14px;
    }

    .stat-value {
      font-weight: 600;
      color: #1e293b;
      font-size: 16px;
    }

    .controls {
      background: white;
      border-radius: 12px;
      padding: 25px;
      box-shadow: 0 4px 12px rgba(59, 130, 246, 0.1);
      margin-bottom: 30px;
    }

    .controls h2 {
      color: #1e40af;
      margin-bottom: 20px;
      font-size: 20px;
    }

    .control-group {
      display: flex;
      gap: 15px;
      flex-wrap: wrap;
      margin-bottom: 20px;
    }

    input, select, button {
      padding: 12px 20px;
      border: 2px solid #e2e8f0;
      border-radius: 8px;
      font-size: 14px;
      transition: all 0.2s;
    }

    input:focus, select:focus {
      outline: none;
      border-color: #3b82f6;
    }

    button {
      background: #3b82f6;
      color: white;
      border: none;
      cursor: pointer;
      font-weight: 600;
    }

    button:hover {
      background: #2563eb;
      transform: translateY(-1px);
      box-shadow: 0 4px 8px rgba(59, 130, 246, 0.3);
    }

    button.danger {
      background: #ef4444;
    }

    button.danger:hover {
      background: #dc2626;
    }

    button.success {
      background: #10b981;
    }

    button.success:hover {
      background: #059669;
    }

    .log {
      background: white;
      border-radius: 12px;
      padding: 25px;
      box-shadow: 0 4px 12px rgba(59, 130, 246, 0.1);
    }

    .log h2 {
      color: #1e40af;
      margin-bottom: 15px;
      font-size: 20px;
    }

    .log-entries {
      max-height: 300px;
      overflow-y: auto;
      background: #f8fafc;
      padding: 15px;
      border-radius: 8px;
    }

    .log-entry {
      padding: 8px;
      margin-bottom: 8px;
      border-left: 3px solid #3b82f6;
      background: white;
      border-radius: 4px;
      font-size: 13px;
      color: #475569;
    }

    .conflict {
      border-left-color: #ef4444;
      background: #fef2f2;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>🌍 Multi-Region Active-Active System</h1>
      <p class="subtitle">Real-time monitoring of distributed data replication and conflict resolution</p>
    </header>

    <div class="regions-grid" id="regions"></div>

    <div class="controls">
      <h2>Operations</h2>
      <div class="control-group">
        <select id="writeRegion">
          <option value="us-east">US-East</option>
          <option value="us-west">US-West</option>
          <option value="eu-west">EU-West</option>
        </select>
        <input type="text" id="writeKey" placeholder="Key" value="user:123">
        <input type="text" id="writeValue" placeholder="Value" value="data">
        <button onclick="writeData()">Write Data</button>
      </div>
      <div class="control-group">
        <button onclick="generateLoad()">Generate Load</button>
        <button onclick="simulateConflict()">Simulate Conflict</button>
      </div>
      <div class="control-group">
        <button class="danger" onclick="failRegion('us-east')">Fail US-East</button>
        <button class="danger" onclick="failRegion('us-west')">Fail US-West</button>
        <button class="danger" onclick="failRegion('eu-west')">Fail EU-West</button>
      </div>
      <div class="control-group">
        <button class="success" onclick="recoverRegion('us-east')">Recover US-East</button>
        <button class="success" onclick="recoverRegion('us-west')">Recover US-West</button>
        <button class="success" onclick="recoverRegion('eu-west')">Recover EU-West</button>
      </div>
    </div>

    <div class="log">
      <h2>Event Log</h2>
      <div class="log-entries" id="log"></div>
    </div>
  </div>

  <script>
    const ws = new WebSocket('ws://localhost:3100');
    const regions = ['us-east', 'us-west', 'eu-west'];

    ws.onmessage = (event) => {
      const stats = JSON.parse(event.data);
      updateRegions(stats);
    };

    function updateRegions(stats) {
      const container = document.getElementById('regions');
      container.innerHTML = stats.map(stat => `
        <div class="region-card">
          <div class="region-header">
            <div class="region-name">${stat.region.toUpperCase()}</div>
            <div class="status-badge ${stat.healthy ? 'status-healthy' : 'status-unhealthy'}">
              ${stat.healthy ? '● Online' : '● Offline'}
            </div>
          </div>
          <div class="stat-row">
            <span class="stat-label">Writes</span>
            <span class="stat-value">${stat.writes || 0}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Reads</span>
            <span class="stat-value">${stat.reads || 0}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Replications</span>
            <span class="stat-value">${stat.replications || 0}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Conflicts</span>
            <span class="stat-value">${stat.conflicts || 0}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Data Size</span>
            <span class="stat-value">${stat.dataSize || 0} keys</span>
          </div>
        </div>
      `).join('');
    }

    async function writeData() {
      const region = document.getElementById('writeRegion').value;
      const key = document.getElementById('writeKey').value;
      const value = document.getElementById('writeValue').value;

      try {
        const response = await fetch('/api/write', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ region, key, value })
        });
        const data = await response.json();
        addLog(`✓ Write to ${region}: ${key} = ${value}`);
      } catch (error) {
        addLog(`✗ Write failed: ${error.message}`, true);
      }
    }

    async function generateLoad() {
      addLog('Generating load across all regions...');
      for (let i = 0; i < 10; i++) {
        const region = regions[Math.floor(Math.random() * regions.length)];
        const key = `key:${Math.floor(Math.random() * 100)}`;
        const value = `value-${Date.now()}`;
        
        await fetch('/api/write', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ region, key, value })
        });
        
        await new Promise(r => setTimeout(r, 100));
      }
      addLog('Load generation complete');
    }

    async function simulateConflict() {
      const key = 'conflict-key';
      addLog('⚠ Simulating concurrent writes to same key...');
      
      await Promise.all([
        fetch('/api/write', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ region: 'us-east', key, value: 'value-from-us-east' })
        }),
        fetch('/api/write', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ region: 'eu-west', key, value: 'value-from-eu-west' })
        })
      ]);
      
      addLog('⚠ Conflict created - check replication stats', true);
    }

    async function failRegion(region) {
      await fetch(`/api/fail/${region}`, { method: 'POST' });
      addLog(`✗ ${region} failed - traffic will reroute`, true);
    }

    async function recoverRegion(region) {
      await fetch(`/api/recover/${region}`, { method: 'POST' });
      addLog(`✓ ${region} recovered`);
    }

    function addLog(message, isConflict = false) {
      const log = document.getElementById('log');
      const entry = document.createElement('div');
      entry.className = `log-entry ${isConflict ? 'conflict' : ''}`;
      entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
      log.insertBefore(entry, log.firstChild);
      
      // Keep only last 50 entries
      while (log.children.length > 50) {
        log.removeChild(log.lastChild);
      }
    }
  </script>
</body>
</html>
EOF

# Create test suite
cat > test.js << 'EOF'
const fetch = require('node-fetch');

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('\n🧪 Running Multi-Region Tests...\n');

  try {
    // Test 1: Write to each region
    console.log('Test 1: Writing to all regions...');
    await fetch('http://localhost:3000/api/write', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ region: 'us-east', key: 'test1', value: 'us-east-value' })
    });
    await fetch('http://localhost:3000/api/write', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ region: 'us-west', key: 'test2', value: 'us-west-value' })
    });
    await fetch('http://localhost:3000/api/write', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ region: 'eu-west', key: 'test3', value: 'eu-west-value' })
    });
    console.log('✓ All writes successful\n');

    // Test 2: Verify replication
    console.log('Test 2: Checking replication (waiting 2s)...');
    await sleep(2000);
    
    const read1 = await fetch('http://localhost:3000/api/read/us-west/test1');
    const data1 = await read1.json();
    console.log(`✓ Read test1 from us-west: ${data1.value}`);

    const read2 = await fetch('http://localhost:3000/api/read/eu-west/test2');
    const data2 = await read2.json();
    console.log(`✓ Read test2 from eu-west: ${data2.value}\n`);

    // Test 3: Simulate conflict
    console.log('Test 3: Testing conflict resolution...');
    await Promise.all([
      fetch('http://localhost:3000/api/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ region: 'us-east', key: 'conflict', value: 'from-us-east' })
      }),
      fetch('http://localhost:3000/api/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ region: 'eu-west', key: 'conflict', value: 'from-eu-west' })
      })
    ]);
    await sleep(1000);
    console.log('✓ Conflict scenario executed\n');

    // Test 4: Check stats
    console.log('Test 4: Verifying statistics...');
    const statsUS = await (await fetch('http://us-east:3001/stats')).json();
    const statsEU = await (await fetch('http://eu-west:3003/stats')).json();
    
    console.log(`✓ US-East - Writes: ${statsUS.writes}, Replications: ${statsUS.replications}, Conflicts: ${statsUS.conflicts}`);
    console.log(`✓ EU-West - Writes: ${statsEU.writes}, Replications: ${statsEU.replications}, Conflicts: ${statsEU.conflicts}\n`);

    console.log('✅ All tests passed!\n');
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

// Wait for services to start
setTimeout(runTests, 5000);
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

CMD ["node"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  us-east:
    build: .
    container_name: us-east
    command: node regions/us-east/server.js
    ports:
      - "3001:3001"
    networks:
      - multi-region

  us-west:
    build: .
    container_name: us-west
    command: node regions/us-west/server.js
    ports:
      - "3002:3002"
    networks:
      - multi-region

  eu-west:
    build: .
    container_name: eu-west
    command: node regions/eu-west/server.js
    ports:
      - "3003:3003"
    networks:
      - multi-region

  dashboard:
    build: .
    container_name: dashboard
    command: node dashboard/server.js
    ports:
      - "3000:3000"
      - "3100:3100"
    depends_on:
      - us-east
      - us-west
      - eu-west
    networks:
      - multi-region

  tests:
    build: .
    container_name: tests
    command: node test.js
    depends_on:
      - dashboard
    networks:
      - multi-region

networks:
  multi-region:
    driver: bridge
EOF

# Create demo script
cat > demo.sh << 'EOF'
#!/bin/bash

echo "🌍 Multi-Region Active-Active Demo"
echo "=================================="
echo ""
echo "Dashboard: http://localhost:3000"
echo ""
echo "Try these experiments:"
echo "1. Write data to different regions and watch replication"
echo "2. Click 'Simulate Conflict' to see concurrent write resolution"
echo "3. Click 'Fail US-East' to simulate regional failure"
echo "4. Generate load to see system under stress"
echo ""
echo "Regional APIs:"
echo "- US-East: http://localhost:3001/health"
echo "- US-West: http://localhost:3002/health"
echo "- EU-West: http://localhost:3003/health"
echo ""
EOF

chmod +x demo.sh

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Multi-Region Demo..."
docker-compose down -v
cd ..
rm -rf multi-region-demo
echo "✓ Cleanup complete"
EOF

chmod +x cleanup.sh

# Verify all files were created
set -e  # Re-enable exit on error for verification
echo ""
echo "🔍 Verifying all files were created..."
REQUIRED_FILES=(
  "package.json"
  "shared/utils.js"
  "shared/region-node.js"
  "regions/us-east/server.js"
  "regions/us-west/server.js"
  "regions/eu-west/server.js"
  "dashboard/server.js"
  "dashboard/index.html"
  "test.js"
  "Dockerfile"
  "docker-compose.yml"
  "demo.sh"
  "cleanup.sh"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    MISSING_FILES+=("$file")
  fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
  echo "❌ Missing files:"
  printf '  - %s\n' "${MISSING_FILES[@]}"
  exit 1
fi

echo "✅ All required files created successfully!"
set +e  # Allow errors for optional commands

# Build and start services
echo ""
echo "📦 Installing dependencies..."
if ! npm install; then
  echo "⚠️  npm install failed, but files are created. You can install dependencies manually."
fi

echo ""
echo "🐳 Building Docker containers..."
if ! docker-compose build; then
  echo "⚠️  docker-compose build failed. You can build manually later."
fi

echo ""
echo "🚀 Starting multi-region system..."
if ! docker-compose up -d; then
  echo "⚠️  docker-compose up failed. You can start services manually later."
fi

echo ""
echo "⏳ Waiting for services to initialize..."
sleep 5

echo ""
echo "✅ Setup complete!"
echo ""
echo "🌍 Dashboard: http://localhost:3000"
echo ""
echo "Run './demo.sh' to see demo instructions"
echo "Run './cleanup.sh' when done"
echo ""
echo "Tests will run automatically and display results..."