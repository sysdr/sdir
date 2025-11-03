const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const redis = require('redis');
const { v4: uuidv4 } = require('uuid');
const cron = require('node-cron');
const PipelineEngine = require('./pipeline-engine');

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

// Redis connection
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.on('error', (err) => console.log('Redis Client Error', err));

async function initRedis() {
  await redisClient.connect();
  console.log('Connected to Redis');
}

// Pipeline engine
const pipelineEngine = new PipelineEngine(redisClient, io);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// API endpoints
app.get('/api/pipelines', async (req, res) => {
  try {
    const pipelines = await pipelineEngine.getAllPipelines();
    res.json(pipelines);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/pipelines/:service/trigger', async (req, res) => {
  try {
    const { service } = req.params;
    const pipelineId = await pipelineEngine.triggerPipeline(service, req.body);
    res.json({ pipelineId, status: 'triggered' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/pipelines/:id', async (req, res) => {
  try {
    const pipeline = await pipelineEngine.getPipeline(req.params.id);
    if (!pipeline) {
      return res.status(404).json({ error: 'Pipeline not found' });
    }
    res.json(pipeline);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/pipelines/:id/approve/:stage', async (req, res) => {
  try {
    await pipelineEngine.approveStage(req.params.id, req.params.stage);
    res.json({ status: 'approved' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/metrics', async (req, res) => {
  try {
    const metrics = pipelineEngine.getMetrics();
    res.json(metrics);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/services', async (req, res) => {
  try {
    const services = await pipelineEngine.getServiceStatus();
    res.json(services);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/security/scan', async (req, res) => {
  try {
    const { service, commit } = req.body;
    const scanResult = await pipelineEngine.performSecurityScan(service, commit);
    res.json(scanResult);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Socket.io connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);
  
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Scheduled pipeline triggers (simulate commits)
cron.schedule('*/30 * * * * *', async () => {
  if (Math.random() > 0.8) { // 20% chance every 30 seconds
    const services = ['frontend', 'backend', 'database'];
    const randomService = services[Math.floor(Math.random() * services.length)];
    
    try {
      await pipelineEngine.triggerPipeline(randomService, {
        commit: Math.random().toString(36).substring(7),
        author: ['alice', 'bob', 'charlie'][Math.floor(Math.random() * 3)],
        message: 'Automated commit simulation'
      });
    } catch (error) {
      console.error('Auto-trigger failed:', error);
    }
  }
});

const PORT = process.env.PORT || 3001;

async function startServer() {
  try {
    await initRedis();
    await pipelineEngine.initialize();
    
    server.listen(PORT, () => {
      console.log(`Pipeline Orchestrator running on port ${PORT}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
