import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import fetch from 'node-fetch';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

let clients = [];

wss.on('connection', (ws) => {
  console.log('Dashboard connected to metrics');
  clients.push(ws);
  
  ws.on('close', () => {
    clients = clients.filter(client => client !== ws);
  });
});

function broadcast(data) {
  const message = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(message);
    }
  });
}

// Collect metrics from all processors
async function collectMetrics() {
  try {
    const [traditional, optimized, generator] = await Promise.all([
      fetch('http://traditional-processor:3002/stats').then(r => r.json()),
      fetch('http://optimized-processor:3003/stats').then(r => r.json()),
      fetch('http://packet-generator:3001/health').then(r => r.json())
    ]);
    
    const tradAvg = parseFloat(traditional.avgLatency) || 0;
    const optAvg = parseFloat(optimized.avgLatency) || 0;
    const tradP99 = parseFloat(traditional.p99) || 0;
    const optP99 = parseFloat(optimized.p99) || 0;
    const avgImprovement = (tradAvg > 0) ? (((tradAvg - optAvg) / tradAvg) * 100).toFixed(1) : '0.0';
    const p99Improvement = (tradP99 > 0) ? (((tradP99 - optP99) / tradP99) * 100).toFixed(1) : '0.0';
    
    const metrics = {
      timestamp: Date.now(),
      traditional,
      optimized,
      generator: generator || { packetsGenerated: 0 },
      improvement: {
        avgLatency: avgImprovement,
        p99: p99Improvement
      }
    };
    
    broadcast({ type: 'metrics_update', data: metrics });
    
  } catch (error) {
    console.error('Error collecting metrics:', error.message);
  }
}

// Collect metrics every 500ms
setInterval(collectMetrics, 500);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', clients: clients.length });
});

const PORT = 3004;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`📊 Metrics Collector running on port ${PORT}`);
});
