const express = require('express');
const cors = require('cors');
const { createServer } = require('http');

const app = express();
app.use(cors());
app.use(express.json());

// Simulated resources (chunks)
const CHUNK_COUNT = 50;
const CHUNK_SIZE = 64 * 1024; // 64KB per chunk

let stats = {
  totalRequests: 0,
  activeStreams: 0,
  stalledStreams: 0,
  totalStalls: 0,  // Cumulative - streams that experienced packet loss
  completedStreams: 0,
  avgLatency: 0,
  packetLoss: 0
};

// Middleware to simulate packet loss (HTTP/2: TCP blocks ALL streams when one has loss)
function simulatePacketLoss(req, res, next) {
  const lossRate = parseFloat(process.env.PACKET_LOSS || 0.01);
  
  if (Math.random() < lossRate) {
    // In HTTP/2 over TCP, one stalled stream blocks ALL multiplexed streams
    const delay = Math.floor(Math.random() * 500) + 200; // 200-700ms delay
    stats.stalledStreams++;
    stats.totalStalls++;
    
    setTimeout(() => {
      stats.stalledStreams--;
      next();
    }, delay);
  } else {
    next();
  }
}

// Endpoint to fetch a chunk
app.get('/chunk/:id', simulatePacketLoss, (req, res) => {
  const chunkId = parseInt(req.params.id);
  const startTime = Date.now();
  
  stats.totalRequests++;
  stats.activeStreams++;
  
  // Simulate chunk data
  const chunk = Buffer.alloc(CHUNK_SIZE);
  chunk.fill(`chunk-${chunkId}`);
  
  const latency = Date.now() - startTime;
  stats.avgLatency = (stats.avgLatency * stats.completedStreams + latency) / (stats.completedStreams + 1);
  stats.completedStreams++;
  stats.activeStreams--;
  
  res.json({
    chunkId,
    size: CHUNK_SIZE,
    latency,
    timestamp: Date.now(),
    protocol: 'HTTP/2'
  });
});

// Stats endpoint
app.get('/stats', (req, res) => {
  res.json({
    ...stats,
    protocol: 'HTTP/2',
    timestamp: Date.now()
  });
});

// Config endpoint
app.post('/config', (req, res) => {
  if (req.body.packetLoss !== undefined) {
    process.env.PACKET_LOSS = req.body.packetLoss;
    stats.packetLoss = req.body.packetLoss;
  }
  res.json({ success: true, packetLoss: process.env.PACKET_LOSS });
});

const server = createServer(app);

server.listen(8443, '0.0.0.0', () => {
  console.log('HTTP/2 Server (TCP simulation) running on http://localhost:8443');
  console.log('Note: Simulates HTTP/2 over TCP head-of-line blocking behavior.');
});
