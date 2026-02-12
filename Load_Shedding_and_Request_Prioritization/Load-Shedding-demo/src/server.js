import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import { PriorityClassifier } from './classifier.js';
import { LoadShedder } from './shedder.js';
import os from 'os';

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

const classifier = new PriorityClassifier();
const shedder = new LoadShedder();

let requestQueue = [];
let processingRequests = 0;
const MAX_CONCURRENT = 100;

// Simulate CPU load calculation
function getCpuLoad() {
  const cpus = os.cpus();
  let totalIdle = 0;
  let totalTick = 0;
  
  cpus.forEach(cpu => {
    for (let type in cpu.times) {
      totalTick += cpu.times[type];
    }
    totalIdle += cpu.times.idle;
  });
  
  const idle = totalIdle / cpus.length;
  const total = totalTick / cpus.length;
  const usage = 100 - (100 * idle / total);
  
  // Add simulated load based on queue depth
  const simulatedLoad = Math.min(40, requestQueue.length / 10);
  return Math.min(100, usage + simulatedLoad);
}

// Update metrics periodically
setInterval(() => {
  const latencies = requestQueue.map(r => Date.now() - r.startTime);
  const p99Latency = latencies.length > 0 
    ? latencies.sort((a, b) => a - b)[Math.floor(latencies.length * 0.99)] || 0
    : 0;
    
  shedder.updateMetrics(
    getCpuLoad(),
    requestQueue.length,
    p99Latency,
    processingRequests
  );
}, 100);

// Middleware to handle load shedding
app.use((req, res, next) => {
  const classification = classifier.classify(req);
  req.priority = classification;
  
  if (!shedder.shouldAccept(classification.priority)) {
    return res.status(503).json({
      error: 'Service temporarily unavailable',
      reason: 'Load shedding active',
      priority: classification.name,
      retryAfter: 5
    });
  }
  
  next();
});

// Simulate request processing
async function processRequest(req, res) {
  processingRequests++;
  
  // Simulate processing time based on priority
  const processingTime = {
    0: 50,   // CRITICAL - fast processing
    1: 100,  // IMPORTANT
    2: 150,  // NORMAL
    3: 200   // BACKGROUND - slower
  }[req.priority.priority];
  
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  processingRequests--;
  
  res.json({
    status: 'success',
    priority: req.priority.name,
    processingTime,
    queueTime: Date.now() - req.startTime - processingTime
  });
}

// API endpoints
app.get('/api/checkout', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/payment', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/order', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/user', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/search', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/browse', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/analytics', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

app.get('/api/recommendations', async (req, res) => {
  req.startTime = Date.now();
  await processRequest(req, res);
});

// Stats endpoint
app.get('/api/stats', (req, res) => {
  res.json(shedder.getStats());
});

// Serve UI
app.use(express.static('ui'));

// WebSocket for real-time updates
wss.on('connection', (ws) => {
  const interval = setInterval(() => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify(shedder.getStats()));
    }
  }, 100);
  
  ws.on('close', () => clearInterval(interval));
});

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Load Shedding Demo running on port ${PORT}`);
});
