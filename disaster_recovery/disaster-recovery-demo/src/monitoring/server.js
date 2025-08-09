const express = require('express');
const winston = require('winston');
const Docker = require('dockerode');

const app = express();
app.use(express.json());

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: '/app/logs/disaster-injector.log' }),
    new winston.transports.Console()
  ]
});

// Docker client
const docker = new Docker({socketPath: '/var/run/docker.sock'});

// Monitoring functions
const monitorContainerHealth = async () => {
  try {
    const containers = await docker.listContainers();
    const healthyContainers = containers.filter(c => c.State === 'running');
    
    logger.info('Container health check', { 
      total: containers.length, 
      healthy: healthyContainers.length 
    });
    
    return { total: containers.length, healthy: healthyContainers.length };
  } catch (error) {
    logger.error('Container health check failed:', error);
    return { total: 0, healthy: 0 };
  }
};

// Chaos engineering functions
const injectNetworkPartition = async (containerName, duration = 30000) => {
  try {
    const container = docker.getContainer(containerName);
    
    // Simulate network partition by pausing container
    await container.pause();
    logger.warn(`Network partition injected for ${containerName}`);
    
    setTimeout(async () => {
      await container.unpause();
      logger.info(`Network partition resolved for ${containerName}`);
    }, duration);
    
    return { success: true, duration };
  } catch (error) {
    logger.error('Network partition injection failed:', error);
    return { success: false, error: error.message };
  }
};

// API endpoints
app.get('/health', (req, res) => {
  res.json({
    service: 'disaster-injector',
    status: 'healthy',
    timestamp: new Date().toISOString()
  });
});

app.get('/monitor/containers', async (req, res) => {
  const health = await monitorContainerHealth();
  res.json(health);
});

app.post('/chaos/network-partition/:container', async (req, res) => {
  const { container } = req.params;
  const { duration = 30000 } = req.body;
  
  const result = await injectNetworkPartition(container, duration);
  res.json(result);
});

// Start monitoring service
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  logger.info(`Disaster injector service started on port ${PORT}`);
  
  // Start periodic health monitoring
  setInterval(monitorContainerHealth, 30000);
});
