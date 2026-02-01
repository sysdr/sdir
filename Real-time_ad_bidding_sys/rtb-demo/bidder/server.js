const express = require('express');
const Redis = require('ioredis');
const { LatencyTracker } = require('./shared/utils');

const app = express();
const PORT = parseInt(process.env.PORT || '3003');
const STRATEGY = process.env.STRATEGY || 'cached';
const BIDDER_NAME = process.env.BIDDER_NAME || 'Bidder';

app.use(express.json());

// Redis for caching
const redis = new Redis({
  host: 'redis',
  port: 6379,
  retryStrategy: (times) => Math.min(times * 50, 2000)
});

const bidTracker = new LatencyTracker();

// Pre-compute bid prices for segments (simulating cached strategy)
const segmentBids = {
  'tech': { base: 2.5, multiplier: 1.3 },
  'sports': { base: 1.8, multiplier: 1.1 },
  'fashion': { base: 2.2, multiplier: 1.2 },
  'travel': { base: 2.0, multiplier: 1.15 },
  'finance': { base: 3.0, multiplier: 1.4 }
};

// Simulate expensive ML model inference
async function mlModelInference(bidRequest) {
  // Simulate 30-40ms ML processing
  const delay = 30 + Math.random() * 10;
  await new Promise(resolve => setTimeout(resolve, delay));
  
  const segment = bidRequest.user.segment;
  const basePrice = segmentBids[segment]?.base || 1.0;
  const deviceMultiplier = bidRequest.device.type === 'mobile' ? 1.2 : 1.0;
  
  return basePrice * deviceMultiplier * (1 + Math.random() * 0.3);
}

// Fast cached lookup
async function cachedBidLookup(bidRequest) {
  const cacheKey = `bid:${bidRequest.user.segment}:${bidRequest.device.type}`;
  
  // Try cache first (1-2ms)
  let price = await redis.get(cacheKey);
  
  if (!price) {
    // Cache miss - compute and cache
    const segment = bidRequest.user.segment;
    const config = segmentBids[segment] || { base: 1.0, multiplier: 1.0 };
    price = config.base * (bidRequest.device.type === 'mobile' ? 1.2 : 1.0);
    
    await redis.setex(cacheKey, 300, price); // Cache for 5 minutes
  }
  
  return parseFloat(price) * (1 + Math.random() * 0.1);
}

// Aggressive bidding (minimal processing)
function aggressiveBid(bidRequest) {
  const segment = bidRequest.user.segment;
  const config = segmentBids[segment] || { base: 1.0, multiplier: 1.0 };
  return config.base * config.multiplier * (1 + Math.random() * 0.2);
}

app.post('/bid', async (req, res) => {
  const bidRequest = req.body;
  const startTime = Date.now();
  
  try {
    let price = 0;
    
    // Different strategies have different latency profiles
    switch (STRATEGY) {
      case 'ml':
        price = await mlModelInference(bidRequest);
        break;
      case 'cached':
        price = await cachedBidLookup(bidRequest);
        break;
      case 'aggressive':
        price = aggressiveBid(bidRequest);
        break;
      default:
        price = 1.0;
    }
    
    // Add small random delay to simulate network/processing variance
    const jitter = Math.random() * 5;
    await new Promise(resolve => setTimeout(resolve, jitter));
    
    const latency = Date.now() - startTime;
    bidTracker.track(latency);
    
    // Only bid if above floor price
    if (price >= bidRequest.imp.bidfloor) {
      res.json({
        bid: {
          id: `bid-${Date.now()}`,
          impid: bidRequest.imp.id,
          price: parseFloat(price.toFixed(2)),
          adm: `<ad>${BIDDER_NAME}</ad>`
        },
        price: parseFloat(price.toFixed(2)),
        bidder: BIDDER_NAME,
        latency: latency
      });
    } else {
      res.status(204).send(); // No bid
    }
  } catch (error) {
    console.error('Bid error:', error);
    res.status(500).json({ error: 'Bid processing failed' });
  }
});

app.get('/stats', (req, res) => {
  const stats = bidTracker.getStats();
  res.json({
    bidder: BIDDER_NAME,
    strategy: STRATEGY,
    bids: stats.count,
    latency: {
      p50: stats.p50,
      p95: stats.p95,
      p99: stats.p99,
      avg: stats.avg
    }
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', bidder: BIDDER_NAME, strategy: STRATEGY });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`💰 ${BIDDER_NAME} (${STRATEGY}) running on port ${PORT}`);
});
