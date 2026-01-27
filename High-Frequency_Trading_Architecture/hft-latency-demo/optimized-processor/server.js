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

// Simulate optimized bypass processing
function simulateDirectNICAccess() {
  // Direct memory access, no context switch
  const latency = 0.2 + Math.random() * 0.3; // 0.2-0.5 microseconds
  return latency;
}

function simulateZeroCopy() {
  // No memory copy, DMA directly to application buffer
  const latency = 0.1 + Math.random() * 0.2; // 0.1-0.3 microseconds
  return latency;
}

function simulateCacheOptimized() {
  // Cache-aligned data structures, prefetching
  const latency = 0.05 + Math.random() * 0.15; // 0.05-0.2 microseconds
  return latency;
}

// Connect to packet generator
const ws = new WebSocket('ws://packet-generator:3001');

ws.on('open', () => {
  console.log('📥 Connected to packet generator (optimized mode)');
});

ws.on('message', (data) => {
  const receiveTime = Date.now();
  const message = JSON.parse(data.toString());
  
  if (message.type === 'market_data_batch') {
    // Batch processing for efficiency
    message.packets.forEach(packet => {
      // Simulate optimized processing
      const nicLatency = simulateDirectNICAccess();
      const zeroCopyLatency = simulateZeroCopy();
      const cacheLatency = simulateCacheOptimized();
      
      const totalLatency = nicLatency + zeroCopyLatency + cacheLatency;
      
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
    mode: 'optimized',
    ...stats,
    latencyDistribution: getLatencyDistribution()
  });
});

function getLatencyDistribution() {
  const buckets = { '0-0.5': 0, '0.5-1.0': 0, '1.0-1.5': 0, '1.5-2.0': 0, '2.0+': 0 };
  stats.latencies.forEach(lat => {
    if (lat < 0.5) buckets['0-0.5']++;
    else if (lat < 1.0) buckets['0.5-1.0']++;
    else if (lat < 1.5) buckets['1.0-1.5']++;
    else if (lat < 2.0) buckets['1.5-2.0']++;
    else buckets['2.0+']++;
  });
  return buckets;
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const PORT = 3003;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`⚡ Optimized Processor running on port ${PORT}`);
  console.log(`Processing with kernel bypass simulation...`);
});
