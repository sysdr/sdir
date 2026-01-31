import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  next();
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server });

let clients = [];

// Watermark configuration
const WATERMARK_LAG_MS = 20000; // Watermark trails by 20 seconds
const WINDOW_SIZE_MS = 10000; // 10-second tumbling windows
const ALLOWED_LATENESS_MS = 10000; // Accept late data for 10s after watermark (so 45s-late events get dropped)

// State management
let currentWatermark = Date.now();
let maxEventTime = Date.now();
let windows = new Map(); // windowStart -> { events, triggered, result }
let lateEvents = [];

class Window {
  constructor(start) {
    this.start = start;
    this.end = start + WINDOW_SIZE_MS;
    this.events = [];
    this.triggered = false;
    this.result = null;
    this.updates = 0;
  }
  
  addEvent(event) {
    this.events.push(event);
    this.result = this.computeResult();
    this.updates++;
  }
  
  computeResult() {
    const eventCounts = {};
    let totalValue = 0;
    
    this.events.forEach(evt => {
      eventCounts[evt.type] = (eventCounts[evt.type] || 0) + 1;
      totalValue += evt.value;
    });
    
    return {
      windowStart: this.start,
      windowEnd: this.end,
      totalEvents: this.events.length,
      eventCounts,
      totalValue,
      updatedAt: Date.now(),
      updates: this.updates
    };
  }
}

function getWindowStart(timestamp) {
  return Math.floor(timestamp / WINDOW_SIZE_MS) * WINDOW_SIZE_MS;
}

function processEvent(event) {
  const windowStart = getWindowStart(event.eventTime);
  
  // Update max event time and watermark
  if (event.eventTime > maxEventTime) {
    maxEventTime = event.eventTime;
    currentWatermark = maxEventTime - WATERMARK_LAG_MS;
  }
  
  // Check if event is too late (beyond allowed lateness)
  const windowEnd = windowStart + WINDOW_SIZE_MS;
  const lateness = currentWatermark - windowEnd;
  
  if (lateness > ALLOWED_LATENESS_MS) {
    // Event is too late, drop it
    lateEvents.push({
      ...event,
      droppedAt: Date.now(),
      reason: 'beyond_allowed_lateness',
      lateness
    });
    broadcast({ type: 'late_event_dropped', data: event });
    return;
  }
  
  // Get or create window
  if (!windows.has(windowStart)) {
    windows.set(windowStart, new Window(windowStart));
  }
  
  const window = windows.get(windowStart);
  const wasTriggered = window.triggered;
  
  window.addEvent(event);
  
  // Check if watermark has passed this window
  if (currentWatermark >= windowEnd && !wasTriggered) {
    window.triggered = true;
    broadcast({ 
      type: 'window_triggered', 
      data: {
        ...window.result,
        triggeredBy: 'watermark',
        watermark: currentWatermark
      }
    });
  } else if (wasTriggered) {
    // Window was already triggered, this is a late update
    broadcast({
      type: 'window_updated',
      data: {
        ...window.result,
        triggeredBy: 'late_data',
        lateEvent: event
      }
    });
  }
  
  // Cleanup old windows (beyond allowed lateness)
  cleanupOldWindows();
  
  // Broadcast current state
  broadcastState();
}

function cleanupOldWindows() {
  const cleanupBoundary = currentWatermark - ALLOWED_LATENESS_MS;
  
  for (const [start, window] of windows.entries()) {
    if (window.end < cleanupBoundary) {
      windows.delete(start);
    }
  }
}

function broadcastState() {
  const state = {
    watermark: currentWatermark,
    maxEventTime,
    watermarkLag: maxEventTime - currentWatermark,
    activeWindows: Array.from(windows.values()).map(w => ({
      start: w.start,
      end: w.end,
      eventCount: w.events.length,
      triggered: w.triggered,
      updates: w.updates
    })),
    totalLateEvents: lateEvents.length,
    recentLateEvents: lateEvents.slice(-10)
  };
  
  broadcast({ type: 'state_update', data: state });
}

function broadcast(message) {
  const msg = JSON.stringify(message);
  clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(msg);
    }
  });
}

wss.on('connection', (ws) => {
  console.log('Dashboard connected');
  clients.push(ws);
  
  // Send current state immediately
  broadcastState();
  
  ws.on('close', () => {
    clients = clients.filter(c => c !== ws);
  });
});

app.post('/events', (req, res) => {
  const event = req.body;
  processEvent(event);
  res.json({ received: true });
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    watermark: currentWatermark,
    activeWindows: windows.size
  });
});

app.get('/stats', (req, res) => {
  res.json({
    watermark: currentWatermark,
    maxEventTime,
    watermarkLag: maxEventTime - currentWatermark,
    activeWindows: windows.size,
    totalLateEvents: lateEvents.length,
    windows: Array.from(windows.values()).map(w => w.result)
  });
});

// Periodic watermark advancement (even without new events)
setInterval(() => {
  broadcastState();
}, 1000);

server.listen(3001, '0.0.0.0', () => {
  console.log('Processor running on port 3001');
});
