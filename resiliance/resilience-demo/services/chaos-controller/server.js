const express = require('express');
const axios = require('axios');
const winston = require('winston');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');

const app = express();
const PORT = 3004;

app.use(cors());
app.use(express.json());

// Create HTTP server and WebSocket server
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

// Service endpoints
const services = {
  'web-api': 'http://web-api:3001',
  'database-service': 'http://database-service:3002',
  'cache-service': 'http://cache-service:3003'
};

// Active experiments
let activeExperiments = new Map();

// WebSocket connections
let wsConnections = new Set();

// WebSocket connection handling
wss.on('connection', (ws) => {
  wsConnections.add(ws);
  logger.info('WebSocket client connected');
  
  ws.on('close', () => {
    wsConnections.delete(ws);
    logger.info('WebSocket client disconnected');
  });
});

function broadcastToClients(data) {
  const message = JSON.stringify(data);
  wsConnections.forEach(ws => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(message);
    }
  });
}

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'chaos-controller', 
    status: 'healthy',
    activeExperiments: activeExperiments.size
  });
});

// Get service status
app.get('/services', async (req, res) => {
  const serviceStatus = {};
  
  for (const [name, url] of Object.entries(services)) {
    try {
      const response = await axios.get(`${url}/health`, { timeout: 3000 });
      serviceStatus[name] = {
        status: 'healthy',
        data: response.data
      };
    } catch (error) {
      serviceStatus[name] = {
        status: 'unhealthy',
        error: error.message
      };
    }
  }
  
  res.json(serviceStatus);
});

// Start chaos experiment
app.post('/chaos/start', async (req, res) => {
  const { experimentId, targetService, type, parameters, duration } = req.body;
  
  if (activeExperiments.has(experimentId)) {
    return res.status(400).json({ error: 'Experiment already running' });
  }
  
  logger.info('Starting chaos experiment', { experimentId, targetService, type, parameters });
  
  try {
    const experiment = {
      id: experimentId,
      targetService,
      type,
      parameters,
      duration,
      startTime: Date.now(),
      status: 'running'
    };
    
    activeExperiments.set(experimentId, experiment);
    
    // Apply chaos based on type
    switch (type) {
      case 'latency':
        await axios.post(`${services[targetService]}/chaos/latency`, { latencyMs: parameters.latencyMs });
        break;
      case 'errors':
        await axios.post(`${services[targetService]}/chaos/errors`, { errorRate: parameters.errorRate });
        break;
      case 'cpu':
        await axios.post(`${services[targetService]}/chaos/cpu`, { enabled: true });
        break;
      case 'memory':
        await axios.post(`${services[targetService]}/chaos/memory`, { enabled: true });
        break;
      case 'configure-cache':
        await axios.post(`${services[targetService]}/chaos/configure`, parameters);
        break;
    }
    
    // Broadcast experiment start
    broadcastToClients({
      type: 'experiment-started',
      experiment
    });
    
    // Schedule experiment end
    setTimeout(async () => {
      await stopExperiment(experimentId);
    }, duration * 1000);
    
    res.json({ message: 'Chaos experiment started', experiment });
    
  } catch (error) {
    logger.error('Failed to start experiment', { error: error.message });
    activeExperiments.delete(experimentId);
    res.status(500).json({ error: 'Failed to start experiment' });
  }
});

// Stop chaos experiment
app.post('/chaos/stop/:experimentId', async (req, res) => {
  const experimentId = req.params.experimentId;
  await stopExperiment(experimentId);
  res.json({ message: 'Experiment stopped' });
});

async function stopExperiment(experimentId) {
  const experiment = activeExperiments.get(experimentId);
  if (!experiment) return;
  
  logger.info('Stopping chaos experiment', { experimentId });
  
  try {
    const { targetService, type } = experiment;
    
    // Reset chaos based on type
    switch (type) {
      case 'latency':
        await axios.post(`${services[targetService]}/chaos/latency`, { latencyMs: 0 });
        break;
      case 'errors':
        await axios.post(`${services[targetService]}/chaos/errors`, { errorRate: 0 });
        break;
      case 'cpu':
        await axios.post(`${services[targetService]}/chaos/cpu`, { enabled: false });
        break;
      case 'memory':
        await axios.post(`${services[targetService]}/chaos/memory`, { enabled: false });
        break;
      case 'configure-cache':
        await axios.post(`${services[targetService]}/chaos/configure`, { 
          latencyMs: 0, 
          errorRate: 0, 
          enabled: false 
        });
        break;
    }
    
    experiment.status = 'completed';
    experiment.endTime = Date.now();
    
    // Broadcast experiment end
    broadcastToClients({
      type: 'experiment-stopped',
      experiment
    });
    
    activeExperiments.delete(experimentId);
    
  } catch (error) {
    logger.error('Failed to stop experiment', { error: error.message });
  }
}

// Get active experiments
app.get('/chaos/experiments', (req, res) => {
  const experiments = Array.from(activeExperiments.values());
  res.json(experiments);
});

// Get metrics from all services
app.get('/metrics/all', async (req, res) => {
  const metrics = {};
  
  for (const [name, url] of Object.entries(services)) {
    try {
      const response = await axios.get(`${url}/metrics`, { timeout: 3000 });
      metrics[name] = response.data;
    } catch (error) {
      metrics[name] = { error: error.message };
    }
  }
  
  res.json(metrics);
});

// Test endpoint for manual testing
app.post('/test/user/:id', async (req, res) => {
  const userId = req.params.id;
  const iterations = req.body.iterations || 1;
  const results = [];
  
  for (let i = 0; i < iterations; i++) {
    try {
      const start = Date.now();
      const response = await axios.get(`${services['web-api']}/api/users/${userId}`, { timeout: 10000 });
      const duration = Date.now() - start;
      
      results.push({
        iteration: i + 1,
        success: true,
        duration,
        data: response.data
      });
    } catch (error) {
      results.push({
        iteration: i + 1,
        success: false,
        error: error.message
      });
    }
    
    // Small delay between requests
    if (i < iterations - 1) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  res.json({ userId, results });
});

server.listen(PORT, () => {
  logger.info(`Chaos controller listening on port ${PORT}`);
});
