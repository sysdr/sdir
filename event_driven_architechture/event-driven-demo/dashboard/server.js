const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');
const cors = require('cors');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// WebSocket for real-time updates
wss.on('connection', (ws) => {
  console.log('Dashboard client connected');
  
  ws.on('close', () => {
    console.log('Dashboard client disconnected');
  });
});

// Proxy API calls to services
app.use('/api/orders', (req, res) => {
  // Proxy to order service
  const url = `http://order-service:3001${req.path}`;
  // Simple proxy implementation would go here
  res.json({ message: 'Use direct service calls' });
});

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

server.listen(3000, () => {
  console.log('Dashboard server started on port 3000');
});
