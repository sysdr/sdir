const express = require('express');
const axios = require('axios');
const WebSocket = require('ws');
const { LatencyTracker } = require('./shared/utils');

const app = express();
const PORT = 3001;

app.use(express.json());
app.use(require('cors')());

// WebSocket server for real-time updates
const wss = new WebSocket.Server({ port: 3002 });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcast(data) {
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

// Bidder registry (hostnames match docker-compose service names)
const bidders = [
  { name: 'FastBidder', url: 'http://bidder-cached:3003', strategy: 'cached' },
  { name: 'SmartBidder', url: 'http://bidder-ml:3004', strategy: 'ml' },
  { name: 'AggressiveBidder', url: 'http://bidder-aggressive:3005', strategy: 'aggressive' }
];

const auctionTracker = new LatencyTracker();
let auctionCount = 0;

// Simulate user profiles for bid requests
const userSegments = ['tech', 'sports', 'fashion', 'travel', 'finance'];
const geoLocations = ['US-CA', 'US-NY', 'GB-LND', 'DE-BE', 'JP-TK'];

function generateBidRequest() {
  return {
    id: `auction-${++auctionCount}`,
    timestamp: Date.now(),
    user: {
      id: `user-${Math.floor(Math.random() * 10000)}`,
      segment: userSegments[Math.floor(Math.random() * userSegments.length)],
      geo: geoLocations[Math.floor(Math.random() * geoLocations.length)]
    },
    site: {
      domain: 'example.com',
      page: '/article/tech-news'
    },
    device: {
      type: Math.random() > 0.5 ? 'mobile' : 'desktop'
    },
    imp: {
      id: 'imp-1',
      banner: { w: 728, h: 90 },
      bidfloor: 0.5
    }
  };
}

async function runAuction() {
  const bidRequest = generateBidRequest();
  const auctionStart = Date.now();
  const timeout = 100; // 100ms deadline

  // Fan out to all bidders simultaneously
  const bidPromises = bidders.map(async (bidder) => {
    const bidderStart = Date.now();
    try {
      const response = await axios.post(`${bidder.url}/bid`, bidRequest, {
        timeout: timeout,
        headers: { 'Content-Type': 'application/json' }
      });
      
      const bidderLatency = Date.now() - bidderStart;
      
      return {
        bidder: bidder.name,
        bid: response.data.bid,
        price: response.data.price,
        latency: bidderLatency,
        success: true
      };
    } catch (error) {
      const bidderLatency = Date.now() - bidderStart;
      return {
        bidder: bidder.name,
        bid: null,
        price: 0,
        latency: bidderLatency,
        success: false,
        error: error.code === 'ECONNABORTED' ? 'timeout' : 'error'
      };
    }
  });

  const bids = await Promise.all(bidPromises);
  const auctionLatency = Date.now() - auctionStart;

  // Select winner (highest valid bid)
  const validBids = bids.filter(b => b.success && b.price > 0);
  const winner = validBids.length > 0 
    ? validBids.reduce((max, bid) => bid.price > max.price ? bid : max)
    : null;

  const auctionResult = {
    auctionId: bidRequest.id,
    timestamp: Date.now(),
    totalLatency: auctionLatency,
    bids: bids,
    winner: winner?.bidder || 'no-winner',
    winningPrice: winner?.price || 0,
    metDeadline: auctionLatency <= timeout
  };

  // Track metrics
  auctionTracker.track(auctionLatency, { metDeadline: auctionResult.metDeadline });

  // Broadcast to dashboard
  broadcast({
    type: 'auction',
    data: auctionResult
  });

  return auctionResult;
}

// Stats endpoint
app.get('/stats', (req, res) => {
  const stats = auctionTracker.getStats();
  res.json({
    auctions: stats.count,
    latency: {
      p50: stats.p50,
      p95: stats.p95,
      p99: stats.p99,
      avg: stats.avg
    },
    recentAuctions: auctionTracker.getRecentMeasurements(20)
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'exchange' });
});

// Start continuous auction simulation
setInterval(() => {
  runAuction().catch(console.error);
}, 500); // Run auction every 500ms

app.listen(PORT, '0.0.0.0', () => {
  console.log(`📊 Ad Exchange running on port ${PORT}`);
  console.log(`🔌 WebSocket server on port 3002`);
  console.log(`🎯 Running auctions every 500ms with 100ms deadline`);
});
