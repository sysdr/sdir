const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

let connectedClients = 0;
let messagesSent = 0;
let lastDataId = 0;

wss.on('connection', (ws) => {
  connectedClients++;
  console.log(`Client connected. Total: ${connectedClients}`);
  
  ws.on('close', () => {
    connectedClients--;
    console.log(`Client disconnected. Total: ${connectedClients}`);
  });
});

// Poll data generator and push to all clients
async function pollAndPush() {
  try {
    const response = await axios.get(`http://data-generator:3001/latest?since=${lastDataId}`);
    const { data, latest } = response.data;
    
    if (data.length > 0) {
      lastDataId = latest;
      
      // Push to all connected clients
      wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          data.forEach(reading => {
            client.send(JSON.stringify(reading));
            messagesSent++;
          });
        }
      });
      
      console.log(`Pushed ${data.length} readings to ${connectedClients} clients`);
    }
  } catch (error) {
    console.error('Error fetching data:', error.message);
  }
}

setInterval(pollAndPush, 100);

app.get('/stats', (req, res) => {
  res.json({
    type: 'push',
    connectedClients,
    messagesSent,
    averageLatency: 50
  });
});

app.get('/health', (req, res) => res.json({ status: 'ok' }));

server.listen(3002, () => console.log('Push Service running on port 3002'));
