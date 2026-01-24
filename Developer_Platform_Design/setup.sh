#!/bin/bash

set -e

echo "======================================"
echo "Developer Platform Demo Setup"
echo "======================================"

# Create directory structure
mkdir -p dev-platform/{catalog,deployer,metrics,portal/{public,src},services/{api,web,worker}}

# ============================================
# Service Catalog (Node.js + SQLite)
# ============================================
cat > dev-platform/catalog/server.js << 'EOF'
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

const db = new sqlite3.Database(':memory:');

// Initialize database
db.serialize(() => {
  db.run(`CREATE TABLE services (
    id TEXT PRIMARY KEY,
    name TEXT,
    team TEXT,
    runtime TEXT,
    status TEXT,
    version TEXT,
    dependencies TEXT,
    last_deploy INTEGER
  )`);
  
  // Seed with sample services
  const services = [
    ['api-gateway', 'API Gateway', 'Platform', 'Node.js', 'running', 'v2.3.1', '[]', Date.now()],
    ['user-service', 'User Service', 'Identity', 'Java', 'running', 'v1.8.2', '["postgres"]', Date.now() - 3600000],
    ['payment-service', 'Payment Service', 'Commerce', 'Go', 'running', 'v3.1.0', '["redis","api-gateway"]', Date.now() - 7200000],
    ['notification-worker', 'Notification Worker', 'Communications', 'Python', 'running', 'v1.2.5', '["rabbitmq","user-service"]', Date.now() - 1800000],
    ['analytics-pipeline', 'Analytics Pipeline', 'Data', 'Scala', 'healthy', 'v2.0.1', '["kafka","s3"]', Date.now() - 900000]
  ];
  
  const stmt = db.prepare('INSERT INTO services VALUES (?,?,?,?,?,?,?,?)');
  services.forEach(s => stmt.run(s));
  stmt.finalize();
});

// API endpoints
app.get('/health', (req, res) => res.json({ status: 'healthy' }));

app.get('/api/services', (req, res) => {
  db.all('SELECT * FROM services ORDER BY last_deploy DESC', (err, rows) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(rows.map(r => ({
      ...r,
      dependencies: JSON.parse(r.dependencies)
    })));
  });
});

app.get('/api/services/:id', (req, res) => {
  db.get('SELECT * FROM services WHERE id = ?', [req.params.id], (err, row) => {
    if (err) return res.status(500).json({ error: err.message });
    if (!row) return res.status(404).json({ error: 'Service not found' });
    res.json({ ...row, dependencies: JSON.parse(row.dependencies) });
  });
});

app.post('/api/services/:id/deploy', (req, res) => {
  const { version } = req.body;
  db.run(
    'UPDATE services SET version = ?, last_deploy = ?, status = ? WHERE id = ?',
    [version, Date.now(), 'deploying', req.params.id],
    function(err) {
      if (err) return res.status(500).json({ error: err.message });
      
      // Simulate deployment completion after 3 seconds
      setTimeout(() => {
        db.run('UPDATE services SET status = ? WHERE id = ?', ['running', req.params.id]);
      }, 3000);
      
      res.json({ message: 'Deployment initiated', version });
    }
  );
});

app.listen(3001, () => console.log('Service Catalog running on port 3001'));
EOF

cat > dev-platform/catalog/package.json << 'EOF'
{
  "name": "service-catalog",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "sqlite3": "^5.1.6"
  }
}
EOF

# ============================================
# Deployment Orchestrator
# ============================================
cat > dev-platform/deployer/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

let deployments = [];
let deploymentId = 1000;

// Simulate deployment pipeline stages
const stages = ['validation', 'build', 'test', 'staging', 'production'];

app.post('/api/deploy', async (req, res) => {
  const { service, version, strategy } = req.body;
  
  const deployment = {
    id: deploymentId++,
    service,
    version,
    strategy: strategy || 'rolling',
    status: 'running',
    currentStage: 0,
    stages: stages.map(s => ({ name: s, status: 'pending', startTime: null, endTime: null })),
    startTime: Date.now(),
    endTime: null,
    logs: []
  };
  
  deployments.unshift(deployment);
  
  // Notify catalog about deployment
  try {
    const catalogUrl = process.env.CATALOG_URL || 'http://localhost:3001';
    await fetch(catalogUrl + '/api/services/' + service + '/deploy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ version })
    });
  } catch (err) {
    console.error('Failed to notify catalog:', err.message);
  }
  
  // Notify metrics service about deployment start
  try {
    const metricsUrl = process.env.METRICS_URL || 'http://localhost:3003';
    await fetch(metricsUrl + '/api/metrics/deployment', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'started', duration: 0 })
    });
  } catch (err) {
    console.error('Failed to notify metrics:', err.message);
  }
  
  // Simulate pipeline progression
  processDeployment(deployment);
  
  res.json({ deploymentId: deployment.id, message: 'Deployment started' });
});

async function processDeployment(deployment) {
  for (let i = 0; i < stages.length; i++) {
    deployment.currentStage = i;
    deployment.stages[i].status = 'running';
    deployment.stages[i].startTime = Date.now();
    
    deployment.logs.push({
      time: Date.now(),
      level: 'info',
      message: `Starting ${stages[i]} stage`
    });
    
    // Simulate stage duration
    await new Promise(resolve => setTimeout(resolve, 2000 + Math.random() * 1000));
    
    deployment.stages[i].status = 'success';
    deployment.stages[i].endTime = Date.now();
    
    deployment.logs.push({
      time: Date.now(),
      level: 'success',
      message: `Completed ${stages[i]} stage`
    });
  }
  
  deployment.status = 'success';
  deployment.endTime = Date.now();
  const duration = deployment.endTime - deployment.startTime;
  deployment.logs.push({
    time: Date.now(),
    level: 'success',
    message: `Deployment completed successfully`
  });
  
  // Notify metrics service about deployment completion
  try {
    const metricsUrl = process.env.METRICS_URL || 'http://localhost:3003';
    await fetch(metricsUrl + '/api/metrics/deployment', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'success', duration: Math.floor(duration / 1000) })
    });
  } catch (err) {
    console.error('Failed to notify metrics:', err.message);
  }
}

app.get('/api/deployments', (req, res) => {
  res.json(deployments.slice(0, 20));
});

app.get('/api/deployments/:id', (req, res) => {
  const deployment = deployments.find(d => d.id === parseInt(req.params.id));
  if (!deployment) return res.status(404).json({ error: 'Deployment not found' });
  res.json(deployment);
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

app.listen(3002, () => console.log('Deployment Orchestrator running on port 3002'));
EOF

cat > dev-platform/deployer/package.json << 'EOF'
{
  "name": "deployment-orchestrator",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

# ============================================
# Metrics Aggregator
# ============================================
cat > dev-platform/metrics/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const WebSocket = require('ws');
const app = express();

app.use(cors());
app.use(express.json());

let metrics = {
  totalServices: 5,
  healthyServices: 5,
  activeDeployments: 0,
  totalDeployments: 0,
  successRate: 100,
  avgDeployTime: 0,
  p95DeployTime: 0,
  requestsPerSecond: 0,
  errorRate: 0
};

let timeSeriesData = [];

// Generate realistic metrics
function generateMetrics() {
  const now = Date.now();
  
  metrics.requestsPerSecond = 850 + Math.floor(Math.random() * 300);
  metrics.errorRate = (0.1 + Math.random() * 0.4).toFixed(2);
  metrics.avgDeployTime = (180 + Math.random() * 60).toFixed(0);
  metrics.p95DeployTime = (280 + Math.random() * 80).toFixed(0);
  
  timeSeriesData.push({
    timestamp: now,
    rps: metrics.requestsPerSecond,
    errorRate: parseFloat(metrics.errorRate),
    deployments: metrics.activeDeployments
  });
  
  // Keep last 60 data points
  if (timeSeriesData.length > 60) {
    timeSeriesData.shift();
  }
}

// Update metrics every 2 seconds
setInterval(generateMetrics, 2000);
generateMetrics();

app.get('/api/metrics', (req, res) => {
  res.json(metrics);
});

app.get('/api/metrics/timeseries', (req, res) => {
  res.json(timeSeriesData);
});

app.post('/api/metrics/deployment', (req, res) => {
  const { status, duration } = req.body;
  
  if (status === 'started') {
    metrics.activeDeployments++;
    metrics.totalDeployments++;
  } else if (status === 'success' || status === 'failed') {
    if (metrics.activeDeployments > 0) {
      metrics.activeDeployments--;
    }
    
    if (status === 'success') {
      metrics.successRate = ((metrics.successRate * (metrics.totalDeployments - 1) + 100) / metrics.totalDeployments).toFixed(1);
      if (duration) {
        // Update average deploy time
        const currentAvg = parseFloat(metrics.avgDeployTime) || 0;
        const newAvg = ((currentAvg * (metrics.totalDeployments - 1) + duration) / metrics.totalDeployments).toFixed(0);
        metrics.avgDeployTime = newAvg;
        
        // Update P95 (simplified - just use a weighted average)
        const currentP95 = parseFloat(metrics.p95DeployTime) || 0;
        const newP95 = Math.max(currentP95 * 0.95, duration * 1.05).toFixed(0);
        metrics.p95DeployTime = newP95;
      }
    } else {
      metrics.successRate = ((metrics.successRate * (metrics.totalDeployments - 1)) / metrics.totalDeployments).toFixed(1);
    }
  }
  
  res.json({ message: 'Metrics updated' });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const server = app.listen(3003, () => console.log('Metrics Aggregator running on port 3003'));

// WebSocket for real-time metrics
const wss = new WebSocket.Server({ server, path: '/ws' });

wss.on('connection', (ws) => {
  console.log('Client connected to metrics stream');
  
  const interval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(metrics));
    }
  }, 2000);
  
  ws.on('close', () => {
    clearInterval(interval);
    console.log('Client disconnected from metrics stream');
  });
});
EOF

cat > dev-platform/metrics/package.json << 'EOF'
{
  "name": "metrics-aggregator",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "ws": "^8.14.2"
  }
}
EOF

# ============================================
# Developer Portal (React Frontend)
# ============================================
cat > dev-platform/portal/package.json << 'EOF'
{
  "name": "developer-portal",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "PORT=3000 react-scripts start",
    "build": "react-scripts build"
  },
  "eslintConfig": {
    "extends": ["react-app"]
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version", "last 1 safari version"]
  }
}
EOF

cat > dev-platform/portal/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Developer Platform</title>
</head>
<body>
  <div id="root"></div>
</body>
</html>
EOF

cat > dev-platform/portal/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
EOF

cat > dev-platform/portal/src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [services, setServices] = useState([]);
  const [deployments, setDeployments] = useState([]);
  const [metrics, setMetrics] = useState(null);
  const [activeTab, setActiveTab] = useState('overview');
  const [selectedService, setSelectedService] = useState(null);

  useEffect(() => {
    loadServices();
    loadDeployments();
    loadMetrics();
    
    const interval = setInterval(() => {
      loadDeployments();
      loadMetrics();
    }, 3000);
    
    return () => clearInterval(interval);
  }, []);

  const loadServices = async () => {
    try {
      const res = await fetch('http://localhost:3001/api/services');
      const data = await res.json();
      setServices(data);
    } catch (err) {
      console.error('Failed to load services:', err);
    }
  };

  const loadDeployments = async () => {
    try {
      const res = await fetch('http://localhost:3002/api/deployments');
      const data = await res.json();
      setDeployments(data);
    } catch (err) {
      console.error('Failed to load deployments:', err);
    }
  };

  const loadMetrics = async () => {
    try {
      const res = await fetch('http://localhost:3003/api/metrics');
      const data = await res.json();
      setMetrics(data);
    } catch (err) {
      console.error('Failed to load metrics:', err);
    }
  };

  const triggerDeploy = async (serviceId) => {
    const version = 'v' + Math.floor(Math.random() * 10) + '.' + Math.floor(Math.random() * 10) + '.' + Math.floor(Math.random() * 100);
    try {
      await fetch('http://localhost:3002/api/deploy', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          service: serviceId, 
          version,
          strategy: 'rolling'
        })
      });
      setTimeout(loadDeployments, 500);
    } catch (err) {
      console.error('Failed to trigger deployment:', err);
    }
  };

  const getStatusColor = (status) => {
    if (status === 'running' || status === 'healthy' || status === 'success') return '#10b981';
    if (status === 'deploying') return '#f59e0b';
    if (status === 'pending') return '#6b7280';
    return '#ef4444';
  };

  return (
    <div className="app">
      <div className="header">
        <h1>🚀 Developer Platform</h1>
        <p>Internal Tools Architecture</p>
      </div>

      <div className="tabs">
        <button 
          className={activeTab === 'overview' ? 'active' : ''} 
          onClick={() => setActiveTab('overview')}
        >
          Overview
        </button>
        <button 
          className={activeTab === 'services' ? 'active' : ''} 
          onClick={() => setActiveTab('services')}
        >
          Service Catalog
        </button>
        <button 
          className={activeTab === 'deployments' ? 'active' : ''} 
          onClick={() => setActiveTab('deployments')}
        >
          Deployments
        </button>
        <button 
          className={activeTab === 'metrics' ? 'active' : ''} 
          onClick={() => setActiveTab('metrics')}
        >
          Metrics
        </button>
      </div>

      {activeTab === 'overview' && metrics && (
        <div className="content">
          <div className="metric-cards">
            <div className="metric-card">
              <div className="metric-value">{metrics.totalServices}</div>
              <div className="metric-label">Total Services</div>
              <div className="metric-sublabel">{metrics.healthyServices} healthy</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{metrics.activeDeployments}</div>
              <div className="metric-label">Active Deployments</div>
              <div className="metric-sublabel">{metrics.totalDeployments} total</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{metrics.successRate}%</div>
              <div className="metric-label">Success Rate</div>
              <div className="metric-sublabel">Last 100 deployments</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{metrics.requestsPerSecond}</div>
              <div className="metric-label">Requests/sec</div>
              <div className="metric-sublabel">{metrics.errorRate}% errors</div>
            </div>
          </div>

          <div className="section">
            <h2>Recent Deployments</h2>
            {deployments.slice(0, 5).map(d => (
              <div key={d.id} className="deployment-item">
                <div className="deployment-header">
                  <span className="deployment-service">{d.service}</span>
                  <span className="deployment-version">{d.version}</span>
                  <span 
                    className="status-badge" 
                    style={{ backgroundColor: getStatusColor(d.status) }}
                  >
                    {d.status}
                  </span>
                </div>
                <div className="deployment-progress">
                  {d.stages.map((stage, i) => (
                    <div key={i} className="stage-indicator">
                      <div 
                        className="stage-dot" 
                        style={{ 
                          backgroundColor: getStatusColor(stage.status),
                          opacity: stage.status === 'pending' ? 0.3 : 1
                        }}
                      />
                      <span className="stage-name">{stage.name}</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'services' && (
        <div className="content">
          <h2>Service Catalog</h2>
          <div className="services-grid">
            {services.map(service => (
              <div key={service.id} className="service-card">
                <div className="service-header">
                  <h3>{service.name}</h3>
                  <span 
                    className="status-badge" 
                    style={{ backgroundColor: getStatusColor(service.status) }}
                  >
                    {service.status}
                  </span>
                </div>
                <div className="service-details">
                  <div className="detail-row">
                    <span className="label">Team:</span>
                    <span>{service.team}</span>
                  </div>
                  <div className="detail-row">
                    <span className="label">Runtime:</span>
                    <span>{service.runtime}</span>
                  </div>
                  <div className="detail-row">
                    <span className="label">Version:</span>
                    <span>{service.version}</span>
                  </div>
                  <div className="detail-row">
                    <span className="label">Dependencies:</span>
                    <span>{service.dependencies.length}</span>
                  </div>
                </div>
                <button 
                  className="deploy-button"
                  onClick={() => triggerDeploy(service.id)}
                >
                  Deploy New Version
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'deployments' && (
        <div className="content">
          <h2>Deployment History</h2>
          {deployments.map(d => (
            <div key={d.id} className="deployment-detail-card">
              <div className="deployment-header">
                <div>
                  <h3>{d.service} @ {d.version}</h3>
                  <p className="deployment-meta">
                    ID: {d.id} | Strategy: {d.strategy} | 
                    Started: {new Date(d.startTime).toLocaleTimeString()}
                  </p>
                </div>
                <span 
                  className="status-badge" 
                  style={{ backgroundColor: getStatusColor(d.status) }}
                >
                  {d.status}
                </span>
              </div>
              
              <div className="deployment-stages">
                {d.stages.map((stage, i) => (
                  <div key={i} className="stage-card">
                    <div className="stage-header">
                      <span>{stage.name}</span>
                      <span 
                        className="stage-status" 
                        style={{ color: getStatusColor(stage.status) }}
                      >
                        {stage.status}
                      </span>
                    </div>
                    {stage.startTime && (
                      <div className="stage-timing">
                        {stage.endTime 
                          ? `${((stage.endTime - stage.startTime) / 1000).toFixed(1)}s`
                          : 'Running...'
                        }
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {activeTab === 'metrics' && metrics && (
        <div className="content">
          <h2>Platform Metrics</h2>
          <div className="metrics-grid">
            <div className="metric-detail-card">
              <h3>Deployment Performance</h3>
              <div className="metric-row">
                <span>Average Deploy Time:</span>
                <strong>{metrics.avgDeployTime}s</strong>
              </div>
              <div className="metric-row">
                <span>P95 Deploy Time:</span>
                <strong>{metrics.p95DeployTime}s</strong>
              </div>
              <div className="metric-row">
                <span>Success Rate:</span>
                <strong>{metrics.successRate}%</strong>
              </div>
              <div className="metric-row">
                <span>Total Deployments:</span>
                <strong>{metrics.totalDeployments}</strong>
              </div>
            </div>

            <div className="metric-detail-card">
              <h3>System Health</h3>
              <div className="metric-row">
                <span>Requests per Second:</span>
                <strong>{metrics.requestsPerSecond}</strong>
              </div>
              <div className="metric-row">
                <span>Error Rate:</span>
                <strong>{metrics.errorRate}%</strong>
              </div>
              <div className="metric-row">
                <span>Healthy Services:</span>
                <strong>{metrics.healthyServices}/{metrics.totalServices}</strong>
              </div>
              <div className="metric-row">
                <span>Active Deployments:</span>
                <strong>{metrics.activeDeployments}</strong>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
EOF

cat > dev-platform/portal/src/App.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

.app {
  max-width: 1400px;
  margin: 0 auto;
  padding: 20px;
}

.header {
  background: white;
  padding: 30px;
  border-radius: 12px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  margin-bottom: 20px;
  text-align: center;
}

.header h1 {
  color: #1e293b;
  font-size: 2.5em;
  margin-bottom: 10px;
}

.header p {
  color: #64748b;
  font-size: 1.1em;
}

.tabs {
  display: flex;
  gap: 10px;
  margin-bottom: 20px;
}

.tabs button {
  flex: 1;
  padding: 15px;
  background: white;
  border: none;
  border-radius: 8px;
  font-size: 1em;
  font-weight: 600;
  color: #64748b;
  cursor: pointer;
  transition: all 0.3s;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.tabs button:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.15);
}

.tabs button.active {
  background: #3b82f6;
  color: white;
}

.content {
  background: white;
  padding: 30px;
  border-radius: 12px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.content h2 {
  color: #1e293b;
  margin-bottom: 20px;
  font-size: 1.8em;
}

.metric-cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 20px;
  margin-bottom: 30px;
}

.metric-card {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 25px;
  border-radius: 10px;
  color: white;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.metric-value {
  font-size: 3em;
  font-weight: bold;
  margin-bottom: 5px;
}

.metric-label {
  font-size: 1.1em;
  opacity: 0.9;
  margin-bottom: 5px;
}

.metric-sublabel {
  font-size: 0.9em;
  opacity: 0.7;
}

.section {
  margin-top: 30px;
}

.deployment-item {
  background: #f8fafc;
  padding: 20px;
  border-radius: 8px;
  margin-bottom: 15px;
  border-left: 4px solid #3b82f6;
}

.deployment-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 15px;
}

.deployment-service {
  font-weight: 600;
  font-size: 1.1em;
  color: #1e293b;
}

.deployment-version {
  color: #64748b;
  font-size: 0.9em;
}

.status-badge {
  padding: 5px 12px;
  border-radius: 20px;
  color: white;
  font-size: 0.85em;
  font-weight: 600;
}

.deployment-progress {
  display: flex;
  gap: 20px;
  align-items: center;
}

.stage-indicator {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 5px;
}

.stage-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
}

.stage-name {
  font-size: 0.75em;
  color: #64748b;
  text-transform: capitalize;
}

.services-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 20px;
}

.service-card {
  background: #f8fafc;
  padding: 20px;
  border-radius: 10px;
  border: 2px solid #e2e8f0;
  transition: all 0.3s;
}

.service-card:hover {
  border-color: #3b82f6;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.2);
  transform: translateY(-2px);
}

.service-header {
  display: flex;
  justify-content: space-between;
  align-items: start;
  margin-bottom: 15px;
}

.service-header h3 {
  color: #1e293b;
  font-size: 1.2em;
}

.service-details {
  margin-bottom: 15px;
}

.detail-row {
  display: flex;
  justify-content: space-between;
  padding: 8px 0;
  border-bottom: 1px solid #e2e8f0;
}

.detail-row .label {
  color: #64748b;
  font-weight: 500;
}

.deploy-button {
  width: 100%;
  padding: 12px;
  background: #3b82f6;
  color: white;
  border: none;
  border-radius: 6px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
}

.deploy-button:hover {
  background: #2563eb;
  transform: scale(1.02);
}

.deployment-detail-card {
  background: #f8fafc;
  padding: 25px;
  border-radius: 10px;
  margin-bottom: 20px;
  border: 2px solid #e2e8f0;
}

.deployment-meta {
  color: #64748b;
  font-size: 0.9em;
  margin-top: 5px;
}

.deployment-stages {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 15px;
  margin-top: 20px;
}

.stage-card {
  background: white;
  padding: 15px;
  border-radius: 8px;
  border: 1px solid #e2e8f0;
}

.stage-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.stage-header span:first-child {
  font-weight: 600;
  color: #1e293b;
  text-transform: capitalize;
}

.stage-status {
  font-size: 0.85em;
  font-weight: 600;
  text-transform: capitalize;
}

.stage-timing {
  color: #64748b;
  font-size: 0.9em;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
  gap: 20px;
}

.metric-detail-card {
  background: #f8fafc;
  padding: 25px;
  border-radius: 10px;
  border: 2px solid #e2e8f0;
}

.metric-detail-card h3 {
  color: #1e293b;
  margin-bottom: 20px;
  font-size: 1.3em;
}

.metric-row {
  display: flex;
  justify-content: space-between;
  padding: 12px 0;
  border-bottom: 1px solid #e2e8f0;
  color: #64748b;
}

.metric-row strong {
  color: #1e293b;
  font-size: 1.1em;
}
EOF

# ============================================
# Docker Compose
# ============================================
cat > dev-platform/docker-compose.yml << 'EOF'
services:
  catalog:
    build: ./catalog
    ports:
      - "3001:3001"
    networks:
      - platform

  deployer:
    build: ./deployer
    ports:
      - "3002:3002"
    depends_on:
      - catalog
      - metrics
    environment:
      - CATALOG_URL=http://catalog:3001
      - METRICS_URL=http://metrics:3003
    networks:
      - platform

  metrics:
    build: ./metrics
    ports:
      - "3003:3003"
    networks:
      - platform

  portal:
    build: ./portal
    ports:
      - "3000:3000"
    depends_on:
      - catalog
      - deployer
      - metrics
    networks:
      - platform

networks:
  platform:
    driver: bridge
EOF

# ============================================
# Dockerfiles
# ============================================
cat > dev-platform/catalog/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY server.js ./
CMD ["node", "server.js"]
EOF

cat > dev-platform/deployer/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY server.js ./
CMD ["node", "server.js"]
EOF

cat > dev-platform/metrics/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY server.js ./
CMD ["node", "server.js"]
EOF

cat > dev-platform/portal/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install
COPY public ./public
COPY src ./src
ENV DANGEROUSLY_DISABLE_HOST_CHECK=true
CMD ["npm", "start"]
EOF

# ============================================
# Build and Run
# ============================================
echo ""
echo "Building Docker containers..."
cd dev-platform
docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "======================================"
echo "Developer Platform Demo Ready!"
echo "======================================"
echo ""
echo "🌐 Developer Portal: http://localhost:3000"
echo "📚 Service Catalog API: http://localhost:3001"
echo "🚀 Deployment API: http://localhost:3002"
echo "📊 Metrics API: http://localhost:3003"
echo ""
echo "Waiting for services to initialize..."
sleep 15

echo ""
echo "✅ Demo Instructions:"
echo "1. Open http://localhost:3000 in your browser"
echo "2. Explore the Service Catalog to see registered services"
echo "3. Click 'Deploy New Version' to trigger a deployment"
echo "4. Watch the deployment pipeline progress in real-time"
echo "5. Check the Metrics tab for platform health"
echo ""
echo "To stop: docker-compose down"
echo "To clean up: bash cleanup.sh"
echo ""