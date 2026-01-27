import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

let clients = [];
let packetId = 0;
let isRunning = true;

wss.on('connection', (ws) => {
  console.log('Client connected to packet generator');
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

// Simulate market data packets at high frequency
function generateMarketData() {
  const instruments = ['EUR/USD', 'GBP/USD', 'BTC/USD', 'ETH/USD', 'AAPL', 'MSFT', 'GOOGL', 'TSLA'];
  const instrument = instruments[Math.floor(Math.random() * instruments.length)];
  
  return {
    id: ++packetId,
    timestamp: Date.now(),
    instrument,
    bid: (100 + Math.random() * 50).toFixed(4),
    ask: (100.01 + Math.random() * 50).toFixed(4),
    volume: Math.floor(Math.random() * 10000),
    sequenceNumber: packetId
  };
}

// Send packets at high frequency (simulating market data feed)
let batchSize = 10;
setInterval(() => {
  if (!isRunning) return;
  
  const batch = [];
  for (let i = 0; i < batchSize; i++) {
    batch.push(generateMarketData());
  }
  
  broadcast({
    type: 'market_data_batch',
    packets: batch,
    batchSize: batch.length,
    timestamp: Date.now()
  });
}, 10); // Send batch every 10ms

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', clients: clients.length, packetsGenerated: packetId });
});

app.get('/control/:action', (req, res) => {
  const { action } = req.params;
  if (action === 'start') {
    isRunning = true;
    res.json({ status: 'started' });
  } else if (action === 'stop') {
    isRunning = false;
    res.json({ status: 'stopped' });
  } else if (action === 'batch') {
    batchSize = parseInt(req.query.size) || 10;
    res.json({ status: 'updated', batchSize });
  } else {
    res.status(400).json({ error: 'Invalid action' });
  }
});

const PORT = 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`📡 Packet Generator running on port ${PORT}`);
  console.log(`Generating market data at high frequency...`);
});
