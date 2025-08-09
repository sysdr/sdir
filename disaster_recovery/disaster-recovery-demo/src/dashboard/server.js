const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const axios = require('axios');
const cors = require('cors');
const path = require('path');
const winston = require('winston');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: '/app/logs/dashboard.log' }),
    new winston.transports.Console()
  ]
});

// Service configurations
const services = {
  'payment-service': { url: 'http://payment-service:3000', tier: 1 },
  'inventory-service': { url: 'http://inventory-service:3000', tier: 2 },
  'analytics-service': { url: 'http://analytics-service:3000', tier: 3 }
};

// System state tracking
let systemState = {
  services: {},
  disasters: [],
  backups: { tier1: [], tier2: [], tier3: [] },
  metrics: {
    totalUptime: 0,
    totalDowntime: 0,
    averageRto: 0,
    averageRpo: 0
  }
};

// Fetch service health
const checkServiceHealth = async (serviceName, config) => {
  try {
    const response = await axios.get(`${config.url}/health`, { timeout: 5000 });
    return {
      name: serviceName,
      ...response.data,
      lastCheck: new Date().toISOString(),
      error: null
    };
  } catch (error) {
    return {
      name: serviceName,
      status: 'unhealthy',
      tier: config.tier,
      lastCheck: new Date().toISOString(),
      error: error.message
    };
  }
};

// Monitor all services
const monitorServices = async () => {
  const healthChecks = Object.entries(services).map(([name, config]) => 
    checkServiceHealth(name, config)
  );
  
  const results = await Promise.all(healthChecks);
  
  results.forEach(result => {
    systemState.services[result.name] = result;
  });
  
  // Broadcast updates to connected clients
  io.emit('serviceUpdate', systemState.services);
  
  return systemState.services;
};

// Dashboard API endpoints
app.get('/api/health', async (req, res) => {
  const health = await monitorServices();
  res.json(health);
});

app.get('/api/system-status', (req, res) => {
  res.json(systemState);
});

// Simple health endpoint for readiness checks
app.get('/health', async (req, res) => {
  try {
    const deps = await monitorServices();
    res.json({
      service: 'dashboard',
      status: 'healthy',
      dependencies: Object.keys(deps),
      timestamp: new Date().toISOString()
    });
  } catch (e) {
    res.status(500).json({
      service: 'dashboard',
      status: 'unhealthy',
      error: e.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Disaster simulation endpoints
app.post('/api/simulate-disaster/:serviceName', async (req, res) => {
  try {
    const { serviceName } = req.params;
    const serviceConfig = services[serviceName];
    
    if (!serviceConfig) {
      return res.status(404).json({ error: 'Service not found' });
    }
    
    const response = await axios.post(`${serviceConfig.url}/simulate/disaster`);
    
    const disaster = {
      id: Date.now(),
      serviceName,
      startTime: new Date().toISOString(),
      status: 'active',
      estimatedRecoveryTime: response.data.estimatedRecoveryTime
    };
    
    systemState.disasters.push(disaster);
    
    // Auto-resolve disaster after estimated recovery time
    setTimeout(() => {
      const disasterIndex = systemState.disasters.findIndex(d => d.id === disaster.id);
      if (disasterIndex !== -1) {
        systemState.disasters[disasterIndex].status = 'resolved';
        systemState.disasters[disasterIndex].endTime = new Date().toISOString();
        io.emit('disasterUpdate', systemState.disasters);
      }
    }, response.data.estimatedRecoveryTime * 1000);
    
    io.emit('disasterUpdate', systemState.disasters);
    
    res.json({
      success: true,
      disaster,
      message: `Disaster simulation started for ${serviceName}`
    });
    
  } catch (error) {
    logger.error('Disaster simulation failed:', error);
    res.status(500).json({ error: 'Disaster simulation failed' });
  }
});

app.get('/api/disasters', (req, res) => {
  res.json(systemState.disasters);
});

// Serve dashboard HTML
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// WebSocket connection handling
io.on('connection', (socket) => {
  logger.info('Client connected to dashboard');
  
  // Send current system state
  socket.emit('serviceUpdate', systemState.services);
  socket.emit('disasterUpdate', systemState.disasters);
  
  socket.on('disconnect', () => {
    logger.info('Client disconnected from dashboard');
  });
});

// Start monitoring
setInterval(monitorServices, 5000);

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  logger.info(`Dashboard server started on port ${PORT}`);
});
