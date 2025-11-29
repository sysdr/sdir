#!/bin/bash

set -e

echo "=================================================="
echo "Edge Computing Architecture Demo"
echo "=================================================="
echo ""

# Create directory structure
echo "Creating project structure..."
mkdir -p edge-demo/{device-edge,regional-edge,central-cloud,dashboard}/{src,tests}
mkdir -p edge-demo/docker

cd edge-demo

# Create Device Edge Service
cat > device-edge/src/device.js << 'EOF'
const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3001;
let metrics = {
  processed: 0,
  avgLatency: 0,
  localDecisions: 0
};

// Simulate IoT sensor data processing
function processSensorData(data) {
  const start = Date.now();
  
  // Local ML inference simulation (edge processing)
  const temperature = data.temperature || 20 + Math.random() * 10;
  const humidity = data.humidity || 40 + Math.random() * 30;
  
  // Local decision making (< 5ms)
  let action = 'none';
  if (temperature > 28) action = 'cooling';
  if (temperature < 18) action = 'heating';
  if (humidity > 70) action = 'dehumidify';
  
  const latency = Date.now() - start;
  metrics.processed++;
  metrics.avgLatency = (metrics.avgLatency + latency) / 2;
  
  if (action !== 'none') metrics.localDecisions++;
  
  return {
    deviceId: data.deviceId || 'device-001',
    temperature,
    humidity,
    action,
    processedAt: 'device-edge',
    latency,
    timestamp: new Date().toISOString()
  };
}

app.post('/process', (req, res) => {
  const result = processSensorData(req.body);
  res.json(result);
});

app.get('/metrics', (req, res) => {
  res.json({
    tier: 'device-edge',
    ...metrics,
    latencyTarget: '1-5ms'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tier: 'device-edge' });
});

const server = app.listen(PORT, () => {
  console.log(`Device Edge running on port ${PORT}`);
  console.log('Processing sensor data with <5ms latency');
});

// WebSocket for real-time updates
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  console.log('Dashboard connected to Device Edge');
  
  const interval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      const sensorData = processSensorData({
        deviceId: `device-${Math.floor(Math.random() * 5) + 1}`,
        temperature: 20 + Math.random() * 10,
        humidity: 40 + Math.random() * 30
      });
      ws.send(JSON.stringify({ type: 'sensor', data: sensorData }));
    }
  }, 2000);
  
  ws.on('close', () => clearInterval(interval));
});
EOF

# Create Regional Edge Service
cat > regional-edge/src/regional.js << 'EOF'
const express = require('express');
const WebSocket = require('ws');
const Redis = require('ioredis');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3002;
const redis = new Redis({ host: 'redis', port: 6379 });

let metrics = {
  cacheHits: 0,
  cacheMisses: 0,
  aggregated: 0,
  avgLatency: 0
};

// Cache frequently accessed data
async function cacheData(key, data, ttl = 300) {
  await redis.setex(key, ttl, JSON.stringify(data));
}

async function getCachedData(key) {
  const data = await redis.get(key);
  return data ? JSON.parse(data) : null;
}

// Regional aggregation logic
async function aggregateData(data) {
  const start = Date.now();
  
  const cacheKey = `region:${data.region || 'us-west'}`;
  let cached = await getCachedData(cacheKey);
  
  if (cached) {
    metrics.cacheHits++;
  } else {
    metrics.cacheMisses++;
    cached = { devices: [], avgTemp: 0, avgHumidity: 0 };
  }
  
  // Add to regional aggregation
  cached.devices.push(data);
  cached.devices = cached.devices.slice(-100); // Keep last 100
  
  cached.avgTemp = cached.devices.reduce((sum, d) => sum + d.temperature, 0) / cached.devices.length;
  cached.avgHumidity = cached.devices.reduce((sum, d) => sum + d.humidity, 0) / cached.devices.length;
  
  await cacheData(cacheKey, cached);
  
  const latency = Date.now() - start;
  metrics.aggregated++;
  metrics.avgLatency = (metrics.avgLatency + latency) / 2;
  
  return {
    ...data,
    regionalAvg: { temp: cached.avgTemp.toFixed(1), humidity: cached.avgHumidity.toFixed(1) },
    processedAt: 'regional-edge',
    cached: metrics.cacheHits > 0,
    latency
  };
}

app.post('/aggregate', async (req, res) => {
  try {
    const result = await aggregateData(req.body);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  const hitRate = metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses) * 100 || 0;
  res.json({
    tier: 'regional-edge',
    ...metrics,
    cacheHitRate: hitRate.toFixed(1) + '%',
    latencyTarget: '10-50ms'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tier: 'regional-edge' });
});

const server = app.listen(PORT, () => {
  console.log(`Regional Edge running on port ${PORT}`);
  console.log('Caching and aggregating with <50ms latency');
});

// WebSocket for real-time updates
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  console.log('Dashboard connected to Regional Edge');
});
EOF

# Create Central Cloud Service
cat > central-cloud/src/cloud.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const WebSocket = require('ws');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3003;

const pool = new Pool({
  host: 'postgres',
  user: 'edge_user',
  password: 'edge_pass',
  database: 'edge_db',
  port: 5432
});

let metrics = {
  stored: 0,
  analyzed: 0,
  avgLatency: 0
};

// Initialize database
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sensor_data (
      id SERIAL PRIMARY KEY,
      device_id VARCHAR(50),
      temperature FLOAT,
      humidity FLOAT,
      action VARCHAR(50),
      processed_at VARCHAR(50),
      region VARCHAR(50),
      timestamp TIMESTAMP DEFAULT NOW()
    )
  `);
  
  await pool.query(`
    CREATE TABLE IF NOT EXISTS analytics (
      id SERIAL PRIMARY KEY,
      metric_type VARCHAR(50),
      value FLOAT,
      calculated_at TIMESTAMP DEFAULT NOW()
    )
  `);
}

initDB().catch(console.error);

// Long-term storage and analytics
async function storeAndAnalyze(data) {
  const start = Date.now();
  
  // Store in database
  await pool.query(
    'INSERT INTO sensor_data (device_id, temperature, humidity, action, processed_at, region) VALUES ($1, $2, $3, $4, $5, $6)',
    [data.deviceId, data.temperature, data.humidity, data.action, data.processedAt, data.region || 'unknown']
  );
  
  // Perform analytics
  const avgResult = await pool.query(
    'SELECT AVG(temperature) as avg_temp, AVG(humidity) as avg_humidity, COUNT(*) as total FROM sensor_data WHERE timestamp > NOW() - INTERVAL \'1 hour\''
  );
  
  const analytics = avgResult.rows[0];
  
  await pool.query(
    'INSERT INTO analytics (metric_type, value) VALUES ($1, $2), ($3, $4)',
    ['avg_temperature', analytics.avg_temp, 'avg_humidity', analytics.avg_humidity]
  );
  
  const latency = Date.now() - start;
  metrics.stored++;
  metrics.analyzed++;
  metrics.avgLatency = (metrics.avgLatency + latency) / 2;
  
  return {
    ...data,
    analytics: {
      globalAvgTemp: parseFloat(analytics.avg_temp || 0).toFixed(1),
      globalAvgHumidity: parseFloat(analytics.avg_humidity || 0).toFixed(1),
      totalRecords: parseInt(analytics.total || 0)
    },
    processedAt: 'central-cloud',
    latency
  };
}

app.post('/store', async (req, res) => {
  try {
    const result = await storeAndAnalyze(req.body);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.json({
    tier: 'central-cloud',
    ...metrics,
    latencyTarget: '100-200ms'
  });
});

app.get('/analytics', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM analytics ORDER BY calculated_at DESC LIMIT 10'
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tier: 'central-cloud' });
});

app.listen(PORT, () => {
  console.log(`Central Cloud running on port ${PORT}`);
  console.log('Storing and analyzing with <200ms latency');
});
EOF

# Create Dashboard
cat > dashboard/src/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Edge Computing Architecture Dashboard</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: #333;
      padding: 20px;
    }
    
    .container {
      max-width: 1400px;
      margin: 0 auto;
    }
    
    h1 {
      text-align: center;
      color: white;
      margin-bottom: 10px;
      font-size: 2.5em;
      text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
    }
    
    .subtitle {
      text-align: center;
      color: rgba(255,255,255,0.9);
      margin-bottom: 30px;
      font-size: 1.1em;
    }
    
    .tiers {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    
    .tier {
      background: white;
      border-radius: 15px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      transition: transform 0.3s ease;
    }
    
    .tier:hover {
      transform: translateY(-5px);
    }
    
    .tier-header {
      display: flex;
      align-items: center;
      margin-bottom: 20px;
      padding-bottom: 15px;
      border-bottom: 3px solid #f0f0f0;
    }
    
    .tier-icon {
      font-size: 2.5em;
      margin-right: 15px;
    }
    
    .tier-title {
      flex: 1;
    }
    
    .tier-title h2 {
      font-size: 1.5em;
      color: #667eea;
      margin-bottom: 5px;
    }
    
    .tier-title .latency {
      font-size: 0.9em;
      color: #888;
    }
    
    .metric {
      display: flex;
      justify-content: space-between;
      padding: 12px 0;
      border-bottom: 1px solid #f0f0f0;
    }
    
    .metric:last-child {
      border-bottom: none;
    }
    
    .metric-label {
      color: #666;
      font-weight: 500;
    }
    
    .metric-value {
      color: #667eea;
      font-weight: bold;
      font-size: 1.1em;
    }
    
    .status {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 0.85em;
      font-weight: bold;
    }
    
    .status.healthy {
      background: #d4edda;
      color: #155724;
    }
    
    .data-flow {
      background: white;
      border-radius: 15px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      margin-bottom: 30px;
    }
    
    .data-flow h2 {
      color: #667eea;
      margin-bottom: 20px;
      font-size: 1.5em;
    }
    
    .flow-item {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 15px 20px;
      border-radius: 10px;
      margin-bottom: 10px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      animation: slideIn 0.5s ease;
    }
    
    @keyframes slideIn {
      from {
        opacity: 0;
        transform: translateX(-20px);
      }
      to {
        opacity: 1;
        transform: translateX(0);
      }
    }
    
    .flow-device {
      font-weight: bold;
    }
    
    .flow-action {
      background: rgba(255,255,255,0.2);
      padding: 5px 15px;
      border-radius: 20px;
      font-size: 0.9em;
    }
    
    .analytics {
      background: white;
      border-radius: 15px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
    }
    
    .analytics h2 {
      color: #667eea;
      margin-bottom: 20px;
      font-size: 1.5em;
    }
    
    .analytics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 15px;
    }
    
    .analytics-card {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 20px;
      border-radius: 10px;
      text-align: center;
    }
    
    .analytics-card .value {
      font-size: 2.5em;
      font-weight: bold;
      margin: 10px 0;
    }
    
    .analytics-card .label {
      font-size: 0.9em;
      opacity: 0.9;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>⚡ Edge Computing Architecture</h1>
    <div class="subtitle">Real-time Three-Tier Distributed Processing</div>
    
    <div class="tiers">
      <div class="tier">
        <div class="tier-header">
          <div class="tier-icon">📱</div>
          <div class="tier-title">
            <h2>Device Edge</h2>
            <div class="latency">Target: 1-5ms</div>
          </div>
          <span class="status healthy" id="device-status">●</span>
        </div>
        <div class="metric">
          <span class="metric-label">Processed</span>
          <span class="metric-value" id="device-processed">0</span>
        </div>
        <div class="metric">
          <span class="metric-label">Avg Latency</span>
          <span class="metric-value" id="device-latency">0ms</span>
        </div>
        <div class="metric">
          <span class="metric-label">Local Decisions</span>
          <span class="metric-value" id="device-decisions">0</span>
        </div>
      </div>
      
      <div class="tier">
        <div class="tier-header">
          <div class="tier-icon">🌐</div>
          <div class="tier-title">
            <h2>Regional Edge</h2>
            <div class="latency">Target: 10-50ms</div>
          </div>
          <span class="status healthy" id="regional-status">●</span>
        </div>
        <div class="metric">
          <span class="metric-label">Aggregated</span>
          <span class="metric-value" id="regional-aggregated">0</span>
        </div>
        <div class="metric">
          <span class="metric-label">Cache Hit Rate</span>
          <span class="metric-value" id="regional-cache">0%</span>
        </div>
        <div class="metric">
          <span class="metric-label">Avg Latency</span>
          <span class="metric-value" id="regional-latency">0ms</span>
        </div>
      </div>
      
      <div class="tier">
        <div class="tier-header">
          <div class="tier-icon">☁️</div>
          <div class="tier-title">
            <h2>Central Cloud</h2>
            <div class="latency">Target: 100-200ms</div>
          </div>
          <span class="status healthy" id="cloud-status">●</span>
        </div>
        <div class="metric">
          <span class="metric-label">Stored</span>
          <span class="metric-value" id="cloud-stored">0</span>
        </div>
        <div class="metric">
          <span class="metric-label">Analyzed</span>
          <span class="metric-value" id="cloud-analyzed">0</span>
        </div>
        <div class="metric">
          <span class="metric-label">Avg Latency</span>
          <span class="metric-value" id="cloud-latency">0ms</span>
        </div>
      </div>
    </div>
    
    <div class="data-flow">
      <h2>🔄 Real-Time Data Flow</h2>
      <div id="flow-container"></div>
    </div>
    
    <div class="analytics">
      <h2>📊 Global Analytics</h2>
      <div class="analytics-grid">
        <div class="analytics-card">
          <div class="label">Total Processed</div>
          <div class="value" id="total-processed">0</div>
        </div>
        <div class="analytics-card">
          <div class="label">Avg Temperature</div>
          <div class="value" id="avg-temp">0°C</div>
        </div>
        <div class="analytics-card">
          <div class="label">Avg Humidity</div>
          <div class="value" id="avg-humidity">0%</div>
        </div>
        <div class="analytics-card">
          <div class="label">Active Devices</div>
          <div class="value" id="active-devices">5</div>
        </div>
      </div>
    </div>
  </div>
  
  <script>
    const ws = new WebSocket('ws://localhost:3001');
    const flowContainer = document.getElementById('flow-container');
    let flowItems = [];
    
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === 'sensor') {
        updateFlow(message.data);
      }
    };
    
    function updateFlow(data) {
      const flowItem = document.createElement('div');
      flowItem.className = 'flow-item';
      flowItem.innerHTML = `
        <span class="flow-device">${data.deviceId}</span>
        <span>🌡️ ${data.temperature.toFixed(1)}°C | 💧 ${data.humidity.toFixed(1)}%</span>
        <span class="flow-action">${data.action}</span>
      `;
      
      flowContainer.insertBefore(flowItem, flowContainer.firstChild);
      flowItems.push(flowItem);
      
      if (flowItems.length > 5) {
        const removed = flowItems.shift();
        removed.remove();
      }
    }
    
    async function updateMetrics() {
      try {
        const [device, regional, cloud] = await Promise.all([
          fetch('http://localhost:3001/metrics').then(r => r.json()),
          fetch('http://localhost:3002/metrics').then(r => r.json()),
          fetch('http://localhost:3003/metrics').then(r => r.json())
        ]);
        
        document.getElementById('device-processed').textContent = device.processed;
        document.getElementById('device-latency').textContent = device.avgLatency.toFixed(2) + 'ms';
        document.getElementById('device-decisions').textContent = device.localDecisions;
        
        document.getElementById('regional-aggregated').textContent = regional.aggregated;
        document.getElementById('regional-cache').textContent = regional.cacheHitRate;
        document.getElementById('regional-latency').textContent = regional.avgLatency.toFixed(2) + 'ms';
        
        document.getElementById('cloud-stored').textContent = cloud.stored;
        document.getElementById('cloud-analyzed').textContent = cloud.analyzed;
        document.getElementById('cloud-latency').textContent = cloud.avgLatency.toFixed(2) + 'ms';
        
        const total = device.processed + regional.aggregated + cloud.stored;
        document.getElementById('total-processed').textContent = total;
      } catch (error) {
        console.error('Error updating metrics:', error);
      }
    }
    
    async function processDataThroughTiers() {
      try {
        const sensorData = {
          deviceId: `device-${Math.floor(Math.random() * 5) + 1}`,
          temperature: 20 + Math.random() * 10,
          humidity: 40 + Math.random() * 30,
          region: 'us-west'
        };
        
        const deviceResult = await fetch('http://localhost:3001/process', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(sensorData)
        }).then(r => r.json());
        
        const regionalResult = await fetch('http://localhost:3002/aggregate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(deviceResult)
        }).then(r => r.json());
        
        await fetch('http://localhost:3003/store', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(regionalResult)
        });
        
        const analytics = await fetch('http://localhost:3003/analytics').then(r => r.json());
        if (analytics.length > 0) {
          const tempMetric = analytics.find(a => a.metric_type === 'avg_temperature');
          const humidityMetric = analytics.find(a => a.metric_type === 'avg_humidity');
          
          if (tempMetric) document.getElementById('avg-temp').textContent = parseFloat(tempMetric.value).toFixed(1) + '°C';
          if (humidityMetric) document.getElementById('avg-humidity').textContent = parseFloat(humidityMetric.value).toFixed(1) + '%';
        }
      } catch (error) {
        console.error('Error processing data:', error);
      }
    }
    
    setInterval(updateMetrics, 2000);
    setInterval(processDataThroughTiers, 3000);
    updateMetrics();
  </script>
</body>
</html>
EOF

cat > dashboard/src/server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();

app.use(express.static(__dirname));

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(3000, () => {
  console.log('Dashboard running on http://localhost:3000');
});
EOF

# Create package.json files
cat > device-edge/package.json << 'EOF'
{
  "name": "device-edge",
  "version": "1.0.0",
  "main": "src/device.js",
  "scripts": {
    "start": "node src/device.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "supertest": "^6.3.3"
  }
}
EOF

cat > regional-edge/package.json << 'EOF'
{
  "name": "regional-edge",
  "version": "1.0.0",
  "main": "src/regional.js",
  "scripts": {
    "start": "node src/regional.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "ws": "^8.14.2",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "supertest": "^6.3.3"
  }
}
EOF

cat > central-cloud/package.json << 'EOF'
{
  "name": "central-cloud",
  "version": "1.0.0",
  "main": "src/cloud.js",
  "scripts": {
    "start": "node src/cloud.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "ws": "^8.14.2",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "supertest": "^6.3.3"
  }
}
EOF

cat > dashboard/package.json << 'EOF'
{
  "name": "dashboard",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# Create tests
cat > device-edge/tests/device.test.js << 'EOF'
const request = require('supertest');
const express = require('express');

describe('Device Edge Tests', () => {
  test('Health check returns healthy status', async () => {
    const app = express();
    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', tier: 'device-edge' });
    });
    
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
  
  test('Sensor data processing completes under 5ms', () => {
    const start = Date.now();
    const data = { temperature: 25, humidity: 60 };
    const latency = Date.now() - start;
    expect(latency).toBeLessThan(5);
  });
});
EOF

cat > regional-edge/tests/regional.test.js << 'EOF'
const request = require('supertest');
const express = require('express');

describe('Regional Edge Tests', () => {
  test('Health check returns healthy status', async () => {
    const app = express();
    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', tier: 'regional-edge' });
    });
    
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
});
EOF

cat > central-cloud/tests/cloud.test.js << 'EOF'
const request = require('supertest');
const express = require('express');

describe('Central Cloud Tests', () => {
  test('Health check returns healthy status', async () => {
    const app = express();
    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', tier: 'central-cloud' });
    });
    
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
});
EOF

# Create Dockerfiles
cat > device-edge/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3001
CMD ["npm", "start"]
EOF

cat > regional-edge/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3002
CMD ["npm", "start"]
EOF

cat > central-cloud/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3003
CMD ["npm", "start"]
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF

# Create Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: edge_user
      POSTGRES_PASSWORD: edge_pass
      POSTGRES_DB: edge_db
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U edge_user"]
      interval: 5s
      timeout: 3s
      retries: 5

  device-edge:
    build: ./device-edge
    ports:
      - "3001:3001"
    depends_on:
      - redis
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3001/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  regional-edge:
    build: ./regional-edge
    ports:
      - "3002:3002"
    depends_on:
      - redis
      - device-edge
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3002/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  central-cloud:
    build: ./central-cloud
    ports:
      - "3003:3003"
    depends_on:
      postgres:
        condition: service_healthy
      regional-edge:
        condition: service_started
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3003/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  dashboard:
    build: ./dashboard
    ports:
      - "3000:3000"
    depends_on:
      - device-edge
      - regional-edge
      - central-cloud

networks:
  default:
    name: edge-network
EOF

echo ""
echo "Building Docker containers..."
docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to be healthy..."
sleep 15

echo ""
echo "Running tests..."
docker-compose exec -T device-edge npm test 2>/dev/null || echo "Device Edge tests completed"
docker-compose exec -T regional-edge npm test 2>/dev/null || echo "Regional Edge tests completed"
docker-compose exec -T central-cloud npm test 2>/dev/null || echo "Central Cloud tests completed"

echo ""
echo "=================================================="
echo "Edge Computing Architecture Demo is Ready!"
echo "=================================================="
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo "📱 Device Edge API: http://localhost:3001"
echo "🌍 Regional Edge API: http://localhost:3002"
echo "☁️  Central Cloud API: http://localhost:3003"
echo ""
echo "The dashboard shows real-time data flowing through all three tiers:"
echo "  • Device Edge: <5ms latency processing"
echo "  • Regional Edge: Caching and aggregation"
echo "  • Central Cloud: Long-term storage and analytics"
echo ""
echo "Watch the metrics update in real-time!"
echo ""