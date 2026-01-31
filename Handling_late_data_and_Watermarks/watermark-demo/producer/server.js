import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

let clients = [];
let eventSequence = 0;

// Configuration for late data simulation
const LATE_DATA_PROBABILITY = 0.22; // 22% of events arrive late (more late data so drops are visible)
const MAX_LATE_DELAY_MS = 50000; // Up to 50 seconds late (ensures some exceed 10s allowed lateness)

// Event types with weights
const EVENT_TYPES = [
  { type: 'page_view', weight: 60, value: 0 },
  { type: 'add_to_cart', weight: 25, value: 50 },
  { type: 'purchase', weight: 15, value: 200 }
];

function weightedRandom(items) {
  const totalWeight = items.reduce((sum, item) => sum + item.weight, 0);
  let random = Math.random() * totalWeight;
  
  for (const item of items) {
    random -= item.weight;
    if (random <= 0) return item;
  }
  return items[0];
}

function generateEvent() {
  const eventType = weightedRandom(EVENT_TYPES);
  const now = Date.now();
  
  // Simulate late data
  const isLate = Math.random() < LATE_DATA_PROBABILITY;
  const delay = isLate ? Math.floor(Math.random() * MAX_LATE_DELAY_MS) : 0;
  
  const event = {
    id: `evt_${++eventSequence}`,
    type: eventType.type,
    userId: `user_${Math.floor(Math.random() * 1000)}`,
    productId: `prod_${Math.floor(Math.random() * 50)}`,
    value: eventType.value,
    eventTime: now - delay, // Event time is in the past if late
    processingTime: now,
    isLate: isLate,
    lateBy: delay
  };
  
  return event;
}

function broadcastEvent(event) {
  const message = JSON.stringify({ type: 'event', data: event });
  clients.forEach(client => {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(message);
    }
  });
}

wss.on('connection', (ws) => {
  console.log('New client connected');
  clients.push(ws);
  
  ws.on('close', () => {
    clients = clients.filter(client => client !== ws);
    console.log('Client disconnected');
  });
});

// Generate events at regular intervals
setInterval(() => {
  const event = generateEvent();
  broadcastEvent(event);
  
  // Send to processor
  fetch('http://processor:3001/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(event)
  }).catch(() => {}); // Ignore errors
}, 500); // New event every 500ms

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

server.listen(3000, '0.0.0.0', () => {
  console.log('Producer running on port 3000');
});
