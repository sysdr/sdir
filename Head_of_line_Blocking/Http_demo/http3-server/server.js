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
  packetLoss: 0,
  streamStates: {} // Track individual stream states
};

// Middleware to simulate packet loss (per-stream in HTTP/3)
function simulatePacketLoss(req, res, next) {
  const lossRate = parseFloat(process.env.PACKET_LOSS || 0.01);
  const chunkId = req.params.id;
  
  if (Math.random() < lossRate) {
    // In HTTP/3, only THIS stream is affected
    if (!stats.streamStates[chunkId]) {
      stats.streamStates[chunkId] = { stalled: false };
    }
    
    stats.streamStates[chunkId].stalled = true;
    stats.stalledStreams++;
    stats.totalStalls++;
    
    const delay = Math.floor(Math.random() * 200) + 50; // 50-250ms delay (faster recovery)
    
    setTimeout(() => {
      stats.streamStates[chunkId].stalled = false;
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
    protocol: 'HTTP/3',
    streamStalled: stats.streamStates[chunkId]?.stalled || false
  });
});

// Stats endpoint
app.get('/stats', (req, res) => {
  res.json({
    ...stats,
    protocol: 'HTTP/3',
    timestamp: Date.now(),
    activeStreamCount: Object.keys(stats.streamStates).filter(
      id => stats.streamStates[id].stalled
    ).length
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

server.listen(8444, () => {
  console.log('HTTP/3 Server (QUIC simulation) running on http://localhost:8444');
  console.log('Note: Running over HTTP for demo purposes. In production, HTTP/3 uses QUIC over UDP.');
});
