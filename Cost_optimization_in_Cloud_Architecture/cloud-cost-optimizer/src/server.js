/**
 * server.js — Express HTTP + WebSocket server
 * Serves the dashboard and broadcasts fleet state in real-time
 */

const express    = require('express');
const http       = require('http');
const WebSocket  = require('ws');
const path       = require('path');

const { FleetEngine } = require('./fleet');

const PORT = process.env.PORT || 3000;

const app    = express();
const server = http.createServer(app);
const wss    = new WebSocket.Server({ server });

app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

// Fleet engine instance
const engine = new FleetEngine({
  reservedCount: 6,
  onDemandCount: 2,
  spotCount:     8,
  tickMs:        3000,  // 3-second simulation ticks
});

// Broadcast to all connected WebSocket clients
function broadcast(type, data) {
  const msg = JSON.stringify({ type, data, ts: Date.now() });
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(msg);
    }
  });
}

// Engine event → WebSocket broadcasts
engine.on('state',     data => broadcast('STATE_UPDATE', data));
engine.on('interrupt', data => broadcast('INTERRUPT',    data));
engine.on('replace',   data => broadcast('REPLACE',      data));

// WebSocket connection handler
wss.on('connection', (ws) => {
  console.log('[WS] Client connected');
  // Send current state immediately on connect
  ws.send(JSON.stringify({ type: 'STATE_UPDATE', data: engine.getSnapshot(), ts: Date.now() }));

  ws.on('close', () => console.log('[WS] Client disconnected'));
  ws.on('error', err => console.error('[WS] Error:', err.message));
});

// ---------------------------------------------------------------------------
// REST API
// ---------------------------------------------------------------------------

// GET /api/state — current fleet snapshot
app.get('/api/state', (req, res) => {
  res.json(engine.getSnapshot());
});

// POST /api/interrupt — manually trigger a Spot interruption
app.post('/api/interrupt', (req, res) => {
  const result = engine.forceInterrupt();
  res.json(result);
});

// POST /api/fleet — adjust fleet composition
// Body: { reservedDelta, onDemandDelta, spotDelta }
app.post('/api/fleet', (req, res) => {
  const { reservedDelta = 0, onDemandDelta = 0, spotDelta = 0 } = req.body;
  engine.adjustFleet({
    reservedDelta:  parseInt(reservedDelta,  10),
    onDemandDelta:  parseInt(onDemandDelta,  10),
    spotDelta:      parseInt(spotDelta,      10),
  });
  res.json({ ok: true, state: engine.getSnapshot().metrics });
});

// Health check
app.get('/health', (req, res) => res.json({ status: 'ok', tick: engine.tick }));

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
server.listen(PORT, () => {
  console.log(`\n✓ Cost Optimizer running at http://localhost:${PORT}`);
  console.log('  WebSocket: ws://localhost:' + PORT);
  console.log('  API: POST /api/interrupt — force Spot interruption');
  console.log('  API: POST /api/fleet     — adjust fleet composition\n');
  engine.start();
});

// Graceful shutdown
process.on('SIGTERM', () => { engine.stop(); server.close(); });
process.on('SIGINT',  () => { engine.stop(); server.close(); process.exit(0); });
