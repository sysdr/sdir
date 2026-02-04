const mqtt = require('mqtt');
const express = require('express');
const WebSocket = require('ws');

const app = express();
const port = 3001;

// CORS for dashboard metrics fetch
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  next();
});

// Connect to Mosquitto broker
const client = mqtt.connect('mqtt://mosquitto:1883');

// Track metrics
const metrics = {
  messagesReceived: 0,
  bytesSent: 0,
  bytesReceived: 0,
  activeSubscriptions: 0,
  lastMessages: []
};

client.on('connect', () => {
  console.log('Connected to MQTT broker');
  
  // Subscribe to all home automation topics
  const topics = [
    'home/+/temperature',
    'home/+/motion',
    'home/+/command'
  ];
  
  topics.forEach(topic => {
    client.subscribe(topic, (err) => {
      if (!err) {
        metrics.activeSubscriptions++;
        console.log(`Subscribed to ${topic}`);
      }
    });
  });
});

client.on('message', (topic, message) => {
  metrics.messagesReceived++;
  metrics.bytesReceived += message.length + topic.length;
  
  const msg = {
    topic,
    payload: message.toString(),
    timestamp: Date.now(),
    size: message.length
  };
  
  metrics.lastMessages.unshift(msg);
  if (metrics.lastMessages.length > 20) metrics.lastMessages.pop();
  
  // Broadcast to WebSocket clients
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({ type: 'mqtt', data: msg }));
    }
  });
});

// WebSocket server for real-time updates
const server = app.listen(port, () => {
  console.log(`MQTT service listening on port ${port}`);
});

const wss = new WebSocket.Server({ server });

app.get('/metrics', (req, res) => {
  res.json(metrics);
});

// Simulate device publishers
function startDeviceSimulation() {
  const devices = ['living-room', 'bedroom', 'kitchen'];
  
  setInterval(() => {
    devices.forEach(device => {
      // Temperature sensor
      const temp = (20 + Math.random() * 5).toFixed(1);
      const tempMsg = JSON.stringify({ value: temp, unit: 'C' });
      client.publish(`home/${device}/temperature`, tempMsg, { qos: 1 });
      metrics.bytesSent += tempMsg.length + `home/${device}/temperature`.length;
      
      // Motion detector (random)
      if (Math.random() > 0.7) {
        const motionMsg = JSON.stringify({ detected: true });
        client.publish(`home/${device}/motion`, motionMsg, { qos: 0 });
        metrics.bytesSent += motionMsg.length + `home/${device}/motion`.length;
      }
    });
  }, 2000);
}

setTimeout(startDeviceSimulation, 2000);
