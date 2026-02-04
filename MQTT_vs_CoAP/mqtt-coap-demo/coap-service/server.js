const coap = require('coap');
const express = require('express');
const WebSocket = require('ws');

const app = express();
const port = 3002;

// CORS for dashboard metrics fetch
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  next();
});

// Track metrics
const metrics = {
  requestsReceived: 0,
  bytesSent: 0,
  bytesReceived: 0,
  activeObservers: 0,
  lastMessages: []
};

// Resource state (simulated sensors)
const resources = {
  'living-room': { temperature: 22.5, motion: false, lastUpdate: Date.now() },
  'bedroom': { temperature: 21.0, motion: false, lastUpdate: Date.now() },
  'kitchen': { temperature: 23.2, motion: false, lastUpdate: Date.now() }
};

// Active CoAP observers per room (ObserveWriteStream instances)
const observers = { 'living-room': [], 'bedroom': [], 'kitchen': [] };

function notifyObservers(room, payload) {
  const streams = observers[room] || [];
  const closed = [];
  streams.forEach((stream, i) => {
    try {
      if (!stream.writableEnded) {
        stream.write(payload);
        metrics.bytesSent += payload.length;
      } else {
        closed.push(i);
      }
    } catch (e) {
      closed.push(i);
    }
  });
  closed.reverse().forEach(i => streams.splice(i, 1));
}

// CoAP server
const server = coap.createServer();

server.on('request', (req, res) => {
  metrics.requestsReceived++;
  metrics.bytesReceived += ((req.payload && req.payload.length) || 0) + ((req.url && req.url.length) || 0);
  
  const urlParts = (req.url || '').split('/').filter(p => p);
  
  if (urlParts.length === 2 && urlParts[1] === 'temperature') {
    const room = urlParts[0];
    
    if (resources[room]) {
      const data = {
        value: resources[room].temperature,
        unit: 'C',
        timestamp: resources[room].lastUpdate
      };
      
      const payload = JSON.stringify(data);
      
      // Check if this is an Observe request (Observe: 0 = register)
      const isObserve = req.headers && req.headers['Observe'] === 0;
      
      if (isObserve && res.write) {
        // ObserveWriteStream: use write(), keep connection open
        res.write(payload);
        metrics.bytesSent += payload.length;
        metrics.activeObservers++;
        
        if (!observers[room]) observers[room] = [];
        observers[room].push(res);
        
        res.on('finish', () => {
          const idx = (observers[room] || []).indexOf(res);
          if (idx >= 0) observers[room].splice(idx, 1);
          metrics.activeObservers = Math.max(0, metrics.activeObservers - 1);
        });
        res.on('error', () => {
          const idx = (observers[room] || []).indexOf(res);
          if (idx >= 0) observers[room].splice(idx, 1);
          metrics.activeObservers = Math.max(0, metrics.activeObservers - 1);
        });
        console.log(`Observer registered for ${req.url} (total: ${metrics.activeObservers})`);
      } else {
        // Regular GET: send and close
        res.end(payload);
        metrics.bytesSent += payload.length;
      }
      
      const msg = {
        method: req.method,
        url: req.url,
        payload: payload,
        timestamp: Date.now(),
        size: payload.length
      };
      
      metrics.lastMessages.unshift(msg);
      if (metrics.lastMessages.length > 20) metrics.lastMessages.pop();
      
      // Broadcast to WebSocket clients
      wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify({ type: 'coap', data: msg }));
        }
      });
    } else {
      res.code = '4.04';
      res.end('Not Found');
    }
  } else {
    res.code = '4.04';
    res.end('Not Found');
  }
});

server.listen(5683, () => {
  console.log('CoAP server listening on port 5683');
});

// WebSocket server for dashboard
const httpServer = app.listen(port, () => {
  console.log(`CoAP service listening on port ${port}`);
});

const wss = new WebSocket.Server({ server: httpServer });

app.get('/metrics', (req, res) => {
  res.json(metrics);
});

// Simulate sensor updates and push to observers
function updateSensors() {
  Object.keys(resources).forEach(room => {
    resources[room].temperature = (20 + Math.random() * 5).toFixed(1);
    resources[room].motion = Math.random() > 0.7;
    resources[room].lastUpdate = Date.now();
    
    // Notify all observers of this room
    const payload = JSON.stringify({
      value: resources[room].temperature,
      unit: 'C',
      timestamp: resources[room].lastUpdate
    });
    notifyObservers(room, payload);
  });
}

setInterval(updateSensors, 2000);

// Simulate CoAP clients polling all rooms (regular GET)
function simulateClients() {
  const rooms = ['living-room', 'bedroom', 'kitchen'];
  rooms.forEach(room => {
    const client = coap.request({
      host: 'localhost',
      port: 5683,
      pathname: `/${room}/temperature`,
      method: 'GET'
    });
    client.on('response', () => {});
    client.end();
  });
}

setInterval(simulateClients, 2000);

// Simulate CoAP Observe clients - register as observers to receive push updates
function simulateObservers() {
  const rooms = ['living-room', 'bedroom', 'kitchen'];
  rooms.forEach(room => {
    const req = coap.request({
      host: 'localhost',
      port: 5683,
      pathname: `/${room}/temperature`,
      method: 'GET',
      observe: true
    });
    req.on('response', (res) => {
      res.on('data', () => {}); // Consume updates
    });
    req.on('error', () => {});
    req.end();
  });
}

// Start observer clients - they stay connected and receive push updates
setTimeout(simulateObservers, 1000);
// Re-register if observers drop (e.g. timeout) - run every 30s, only add when below 3
setInterval(() => {
  if (metrics.activeObservers < 3) simulateObservers();
}, 30000);
