const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3001;
let metrics = {
  processed: 0,
  avgLatency: 0,
  localDecisions: 0
};

// Simulate IoT sensor data processing
function processSensorData(data) {
  const start = Date.now();
  
  // Local ML inference simulation (edge processing)
  const temperature = data.temperature || 20 + Math.random() * 10;
  const humidity = data.humidity || 40 + Math.random() * 30;
  
  // Local decision making (< 5ms)
  let action = 'none';
  if (temperature > 28) action = 'cooling';
  if (temperature < 18) action = 'heating';
  if (humidity > 70) action = 'dehumidify';
  
  const latency = Date.now() - start;
  metrics.processed++;
  metrics.avgLatency = (metrics.avgLatency + latency) / 2;
  
  if (action !== 'none') metrics.localDecisions++;
  
  return {
    deviceId: data.deviceId || 'device-001',
    temperature,
    humidity,
    action,
    processedAt: 'device-edge',
    latency,
    timestamp: new Date().toISOString()
  };
}

app.post('/process', (req, res) => {
  const result = processSensorData(req.body);
  res.json(result);
});

app.get('/metrics', (req, res) => {
  res.json({
    tier: 'device-edge',
    ...metrics,
    latencyTarget: '1-5ms'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tier: 'device-edge' });
});

const server = app.listen(PORT, () => {
  console.log(`Device Edge running on port ${PORT}`);
  console.log('Processing sensor data with <5ms latency');
});

// WebSocket for real-time updates
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  console.log('Dashboard connected to Device Edge');
  
  const interval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      const sensorData = processSensorData({
        deviceId: `device-${Math.floor(Math.random() * 5) + 1}`,
        temperature: 20 + Math.random() * 10,
        humidity: 40 + Math.random() * 30
      });
      ws.send(JSON.stringify({ type: 'sensor', data: sensorData }));
    }
  }, 2000);
  
  ws.on('close', () => clearInterval(interval));
});
