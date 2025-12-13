const express = require('express');
const app = express();
const PORT = 4000;

app.use(express.json());

let podStatuses = [];
let totalRequests = 0;
let requestTimes = []; // Track response times for average calculation

// Pods report their status here
app.post('/report', (req, res) => {
  const { pod, healthy, ready, activeRequests, uptime, config } = req.body;
  
  const index = podStatuses.findIndex(p => p.name === pod);
  const status = { name: pod, healthy, ready, activeRequests, uptime, config, lastSeen: Date.now() };
  
  if (index >= 0) {
    podStatuses[index] = status;
  } else {
    podStatuses.push(status);
  }
  
  res.json({ received: true });
});

// Track request metrics
app.post('/api/metrics', (req, res) => {
  const { responseTime } = req.body;
  if (responseTime) {
    requestTimes.push(responseTime);
    // Keep only last 1000 requests for average calculation
    if (requestTimes.length > 1000) {
      requestTimes.shift();
    }
  }
  totalRequests++;
  res.json({ received: true });
});

// Dashboard queries aggregated status
app.get('/api/pods/status', (req, res) => {
  // Remove stale pods (haven't reported in 10 seconds)
  podStatuses = podStatuses.filter(p => Date.now() - p.lastSeen < 10000);
  
  // Calculate average response time from tracked requests
  let avgResponseTime = 0;
  if (requestTimes.length > 0) {
    const sum = requestTimes.reduce((a, b) => a + b, 0);
    avgResponseTime = Math.floor(sum / requestTimes.length);
  }
  
  res.json({
    pods: podStatuses,
    metrics: {
      totalRequests: totalRequests || 0,
      avgResponseTime: avgResponseTime || 0
    }
  });
});

// Load generator
app.post('/api/load/generate', async (req, res) => {
  const { intensity } = req.body;
  const requests = intensity === 'low' ? 10 : intensity === 'medium' ? 50 : 100;
  
  console.log(`Generating ${requests} requests with ${intensity} intensity`);
  
  res.json({ message: `Generating ${requests} requests` });
  
  // Send requests to app pods
  for (let i = 0; i < requests; i++) {
    const startTime = Date.now();
    fetch('http://app-service:3000/api/process')
      .then(async (response) => {
        const responseTime = Date.now() - startTime;
        // Update metrics directly (we're in the aggregator)
        if (responseTime) {
          requestTimes.push(responseTime);
          if (requestTimes.length > 1000) {
            requestTimes.shift();
          }
        }
        totalRequests++;
      })
      .catch(console.error);
    await new Promise(resolve => setTimeout(resolve, 100));
  }
});

// Chaos engineering endpoints
app.post('/api/chaos/:action', async (req, res) => {
  const { action } = req.params;
  const { pod } = req.body;
  
  console.log(`Chaos action: ${action} on pod: ${pod || 'random'}`);
  
  // In real implementation, would forward to specific pod
  // Here we simulate the effect
  res.json({ message: `Chaos action ${action} triggered` });
});

app.listen(PORT, () => {
  console.log(`Aggregator service listening on port ${PORT}`);
});
