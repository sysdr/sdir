import express from 'express';
import WebSocket from 'ws';

const app = express();
let stats = {
  packetsProcessed: 0,
  latencies: [],
  avgLatency: 0,
  p50: 0,
  p95: 0,
  p99: 0
};

// Simulate traditional kernel overhead
function simulateKernelOverhead() {
  // Context switches, system calls, memory copies
  const overhead = 15 + Math.random() * 35; // 15-50 microseconds
  return overhead;
}

function simulateNetworkStack() {
  // TCP/IP stack processing
  const stackLatency = 5 + Math.random() * 15; // 5-20 microseconds
  return stackLatency;
}

function simulateMemoryCopy() {
  // Kernel to user space copy
  const copyLatency = 3 + Math.random() * 7; // 3-10 microseconds
  return copyLatency;
}

// Connect to packet generator
const ws = new WebSocket('ws://packet-generator:3001');

ws.on('open', () => {
  console.log('📥 Connected to packet generator (traditional mode)');
});

ws.on('message', (data) => {
  const receiveTime = Date.now();
  const message = JSON.parse(data.toString());
  
  if (message.type === 'market_data_batch') {
    message.packets.forEach(packet => {
      // Simulate traditional processing delays
      const kernelOverhead = simulateKernelOverhead();
      const stackLatency = simulateNetworkStack();
      const copyLatency = simulateMemoryCopy();
      
      const totalLatency = kernelOverhead + stackLatency + copyLatency;
      
      // Add to stats
      stats.packetsProcessed++;
      stats.latencies.push(totalLatency);
      
      // Keep only last 10000 samples
      if (stats.latencies.length > 10000) {
        stats.latencies.shift();
      }
      
      // Calculate percentiles periodically
      if (stats.packetsProcessed % 100 === 0) {
        calculateStats();
      }
    });
  }
});

function calculateStats() {
  if (stats.latencies.length === 0) return;
  
  const sorted = [...stats.latencies].sort((a, b) => a - b);
  stats.avgLatency = (sorted.reduce((a, b) => a + b, 0) / sorted.length).toFixed(2);
  stats.p50 = sorted[Math.floor(sorted.length * 0.5)].toFixed(2);
  stats.p95 = sorted[Math.floor(sorted.length * 0.95)].toFixed(2);
  stats.p99 = sorted[Math.floor(sorted.length * 0.99)].toFixed(2);
}

app.get('/stats', (req, res) => {
  res.json({
    mode: 'traditional',
    ...stats,
    latencyDistribution: getLatencyDistribution()
  });
});

function getLatencyDistribution() {
  const buckets = { '0-10': 0, '10-20': 0, '20-30': 0, '30-40': 0, '40-50': 0, '50+': 0 };
  stats.latencies.forEach(lat => {
    if (lat < 10) buckets['0-10']++;
    else if (lat < 20) buckets['10-20']++;
    else if (lat < 30) buckets['20-30']++;
    else if (lat < 40) buckets['30-40']++;
    else if (lat < 50) buckets['40-50']++;
    else buckets['50+']++;
  });
  return buckets;
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const PORT = 3002;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`⚙️  Traditional Processor running on port ${PORT}`);
  console.log(`Processing with kernel overhead simulation...`);
});
