const express = require('express');
const app = express();
const WebSocket = require('ws');

app.use(express.json());

// CORS: allow dashboard at localhost:8080 to fetch metrics and post traces
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', 'http://localhost:8080');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

class MetricsCollector {
  constructor() {
    this.metrics = [];
    this.systemMetrics = {
      cpu: 0,
      memory: 0,
      network: 0,
      diskIO: 0
    };
  }

  // Simulates eBPF kernel-level tracing
  captureSystemMetrics() {
    this.systemMetrics = {
      cpu: Math.random() * 80 + 10,
      memory: Math.random() * 70 + 20,
      network: Math.random() * 1000,
      diskIO: Math.random() * 500,
      timestamp: Date.now()
    };

    return this.systemMetrics;
  }

  recordTrace(trace) {
    const enrichedTrace = {
      ...trace,
      timestamp: Date.now(),
      kernelTime: Math.random() * 2,  // eBPF overhead
      userTime: trace.duration || Math.random() * 50
    };

    this.metrics.push(enrichedTrace);
    
    // Keep only last 1000 metrics
    if (this.metrics.length > 1000) {
      this.metrics = this.metrics.slice(-1000);
    }

    return enrichedTrace;
  }

  getMetrics(limit = 50) {
    return {
      recent: this.metrics.slice(-limit),
      system: this.systemMetrics,
      totalTraces: this.metrics.length,
      avgLatency: this.metrics.length > 0
        ? this.metrics.reduce((sum, m) => sum + (m.userTime || 0), 0) / this.metrics.length
        : 0
    };
  }
}

const collector = new MetricsCollector();
collector.captureSystemMetrics();
app.post('/trace', (req, res) => {
  const trace = collector.recordTrace(req.body);
  
  // Broadcast to WebSocket clients
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'trace',
        data: trace
      }));
    }
  });

  res.json(trace);
});

app.get('/metrics', (req, res) => {
  res.json(collector.getMetrics());
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'metrics-collector' });
});

const server = app.listen(3003, () => {
  console.log('📊 Metrics Collector running on port 3003');
});

const wss = new WebSocket.Server({ server });

// Simulate continuous system metrics collection (eBPF-style)
setInterval(() => {
  const metrics = collector.captureSystemMetrics();
  
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'system-metrics',
        data: metrics
      }));
    }
  });
}, 2000);
