import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

const server = createServer(app);
const wss = new WebSocketServer({ server });

let queryLogs = [];
let metrics = {
  totalQueries: 0,
  avgResponseTime: 0,
  servicesInvoked: { users: 0, products: 0, reviews: 0 }
};

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'init', data: { queryLogs, metrics } }));
});

function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

app.post('/log-query', (req, res) => {
  const log = {
    ...req.body,
    timestamp: new Date().toISOString(),
    id: Date.now()
  };
  
  queryLogs.unshift(log);
  if (queryLogs.length > 50) queryLogs.pop();
  
  metrics.totalQueries++;
  metrics.avgResponseTime = ((metrics.avgResponseTime * (metrics.totalQueries - 1)) + log.responseTime) / metrics.totalQueries;
  
  log.services.forEach(service => {
    if (metrics.servicesInvoked[service] !== undefined) {
      metrics.servicesInvoked[service]++;
    }
  });
  
  broadcast({ type: 'query', data: log });
  broadcast({ type: 'metrics', data: metrics });
  
  res.json({ success: true });
});

server.listen(3000, () => {
  console.log('📊 Dashboard running at http://localhost:3000');
});
