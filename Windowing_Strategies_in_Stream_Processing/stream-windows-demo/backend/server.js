import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Configuration
const CONFIG = {
  tumblingWindowSize: 60000,      // 1 minute
  slidingWindowSize: 300000,      // 5 minutes
  slidingWindowSlide: 15000,      // 15 seconds
  sessionInactivityGap: 5000,     // 5 seconds (demo: sessions close so dashboard updates)
  eventsPerSecond: 50             // 50/sec so session gaps occur and all metrics update
};

// Stock symbols for simulation
const SYMBOLS = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'META', 'NVDA', 'NFLX'];

// Data structures for windows
let events = [];
let tumblingWindows = [];
let slidingWindows = [];
let sessionWindows = new Map(); // symbol -> session data

// Broadcast to all connected clients
function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

// Generate realistic stock trade event
function generateTradeEvent() {
  const symbol = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)];
  const basePrice = { AAPL: 175, GOOGL: 140, MSFT: 380, AMZN: 155, 
                      TSLA: 240, META: 350, NVDA: 500, NFLX: 450 };
  
  const price = basePrice[symbol] + (Math.random() - 0.5) * 10;
  const volume = Math.floor(Math.random() * 1000) + 100;
  
  return {
    symbol,
    price: parseFloat(price.toFixed(2)),
    volume,
    timestamp: Date.now()
  };
}

// Process Tumbling Windows (non-overlapping, fixed size)
function processTumblingWindows() {
  const now = Date.now();
  const windowStart = Math.floor(now / CONFIG.tumblingWindowSize) * CONFIG.tumblingWindowSize;
  
  // Get events in current window
  const windowEvents = events.filter(e => 
    e.timestamp >= windowStart && e.timestamp < windowStart + CONFIG.tumblingWindowSize
  );
  
  // Calculate metrics per symbol
  const metrics = {};
  windowEvents.forEach(event => {
    if (!metrics[event.symbol]) {
      metrics[event.symbol] = { prices: [], volumes: 0, count: 0 };
    }
    metrics[event.symbol].prices.push(event.price);
    metrics[event.symbol].volumes += event.volume;
    metrics[event.symbol].count++;
  });
  
  const results = Object.entries(metrics).map(([symbol, data]) => ({
    symbol,
    avgPrice: (data.prices.reduce((a, b) => a + b, 0) / data.prices.length).toFixed(2),
    totalVolume: data.volumes,
    eventCount: data.count,
    windowStart: new Date(windowStart).toISOString(),
    windowEnd: new Date(windowStart + CONFIG.tumblingWindowSize).toISOString()
  }));
  
  // Clean old windows (keep last 5)
  tumblingWindows = [{ timestamp: windowStart, results }, ...tumblingWindows].slice(0, 5);
  
  broadcast({ type: 'tumblingWindow', data: tumblingWindows });
}

// Process Sliding Windows (overlapping windows)
function processSlidingWindows() {
  const now = Date.now();
  
  // Create sliding windows that overlap
  const slides = Math.floor(CONFIG.slidingWindowSize / CONFIG.slidingWindowSlide);
  const currentSlideIndex = Math.floor(now / CONFIG.slidingWindowSlide);
  
  const results = [];
  
  // Process last few slides
  for (let i = 0; i < Math.min(slides, 10); i++) {
    const slideIndex = currentSlideIndex - i;
    const windowEnd = slideIndex * CONFIG.slidingWindowSlide + CONFIG.slidingWindowSlide;
    const windowStart = windowEnd - CONFIG.slidingWindowSize;
    
    // Get events in this sliding window
    const windowEvents = events.filter(e => 
      e.timestamp >= windowStart && e.timestamp < windowEnd
    );
    
    if (windowEvents.length === 0) continue;
    
    // Calculate moving average per symbol
    const metrics = {};
    windowEvents.forEach(event => {
      if (!metrics[event.symbol]) {
        metrics[event.symbol] = { prices: [], volumes: 0 };
      }
      metrics[event.symbol].prices.push(event.price);
      metrics[event.symbol].volumes += event.volume;
    });
    
    const symbolResults = Object.entries(metrics).map(([symbol, data]) => ({
      symbol,
      movingAvg: (data.prices.reduce((a, b) => a + b, 0) / data.prices.length).toFixed(2),
      totalVolume: data.volumes,
      eventCount: windowEvents.length
    }));
    
    results.push({
      windowStart: new Date(windowStart).toISOString(),
      windowEnd: new Date(windowEnd).toISOString(),
      results: symbolResults
    });
  }
  
  slidingWindows = results;
  broadcast({ type: 'slidingWindow', data: slidingWindows });
}

// Process Session Windows (activity-based windows)
function processSessionWindows() {
  const now = Date.now();
  
  // Group events by symbol into sessions based on inactivity gaps
  events.forEach(event => {
    const symbol = event.symbol;
    
    if (!sessionWindows.has(symbol)) {
      // Start new session
      sessionWindows.set(symbol, {
        symbol,
        events: [event],
        startTime: event.timestamp,
        lastEventTime: event.timestamp,
        status: 'active'
      });
    } else {
      const session = sessionWindows.get(symbol);
      
      // Check if event extends existing session or starts new one
      if (event.timestamp - session.lastEventTime <= CONFIG.sessionInactivityGap) {
        // Extend session
        session.events.push(event);
        session.lastEventTime = event.timestamp;
      } else {
        // Close old session and start new one
        session.status = 'closed';
        session.endTime = session.lastEventTime;
        
        // Start new session
        sessionWindows.set(symbol + '_' + event.timestamp, {
          symbol,
          events: [event],
          startTime: event.timestamp,
          lastEventTime: event.timestamp,
          status: 'active'
        });
      }
    }
  });
  
  // Close expired sessions
  sessionWindows.forEach((session, key) => {
    if (session.status === 'active' && 
        now - session.lastEventTime > CONFIG.sessionInactivityGap) {
      session.status = 'closed';
      session.endTime = session.lastEventTime;
    }
  });
  
  // Calculate session metrics
  const sessionResults = Array.from(sessionWindows.values())
    .filter(s => s.status === 'closed')
    .slice(-20) // Keep last 20 closed sessions
    .map(session => {
      const prices = session.events.map(e => e.price);
      const volumes = session.events.reduce((sum, e) => sum + e.volume, 0);
      
      return {
        symbol: session.symbol,
        duration: session.endTime - session.startTime,
        eventCount: session.events.length,
        avgPrice: (prices.reduce((a, b) => a + b, 0) / prices.length).toFixed(2),
        totalVolume: volumes,
        startTime: new Date(session.startTime).toISOString(),
        endTime: new Date(session.endTime).toISOString()
      };
    });
  
  broadcast({ type: 'sessionWindow', data: sessionResults });
}

// Event generator
setInterval(() => {
  const event = generateTradeEvent();
  events.push(event);
  
  // Keep only last 10 minutes of events in memory
  const tenMinutesAgo = Date.now() - 600000;
  events = events.filter(e => e.timestamp > tenMinutesAgo);
  
  // Broadcast raw event
  broadcast({ type: 'newEvent', data: event });
}, 1000 / CONFIG.eventsPerSecond);

// Process windows periodically
setInterval(processTumblingWindows, 5000);  // Every 5 seconds
setInterval(processSlidingWindows, 15000);  // Every 15 seconds (slide interval)
setInterval(processSessionWindows, 10000);  // Every 10 seconds

// WebSocket connection handler
wss.on('connection', (ws) => {
  console.log('Client connected');
  
  // Send current state
  ws.send(JSON.stringify({ type: 'config', data: CONFIG }));
  ws.send(JSON.stringify({ type: 'tumblingWindow', data: tumblingWindows }));
  ws.send(JSON.stringify({ type: 'slidingWindow', data: slidingWindows }));
  
  ws.on('close', () => console.log('Client disconnected'));
});

// API endpoints
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', eventCount: events.length });
});

app.get('/stats', (req, res) => {
  res.json({
    totalEvents: events.length,
    tumblingWindows: tumblingWindows.length,
    slidingWindows: slidingWindows.length,
    sessionWindows: sessionWindows.size
  });
});

const PORT = 3001;
server.listen(PORT, () => {
  console.log(`🎯 Stream Processing Server running on http://localhost:${PORT}`);
  console.log(`📊 WebSocket server ready for connections`);
});
