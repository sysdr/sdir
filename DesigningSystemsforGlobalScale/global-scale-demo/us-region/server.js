const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');

const app = express();
app.use(cors());
app.use(express.json());

const REGION = 'US';
const PORT = 3001;

let redisClient;

// Initialize Redis
async function initRedis() {
  redisClient = createClient({ url: 'redis://redis:6379' });
  await redisClient.connect();
  
  // Initialize sample listings
  const listings = [
    { id: 'us-1', name: 'NYC Loft', region: 'US', price: 250 },
    { id: 'us-2', name: 'SF Studio', region: 'US', price: 180 },
    { id: 'us-3', name: 'LA Beach House', region: 'US', price: 320 }
  ];
  
  for (const listing of listings) {
    await redisClient.hSet(`listing:${listing.id}`, listing);
    await redisClient.set(`availability:${listing.id}`, 'available');
  }
}

// Get regional listings
app.get('/listings', async (req, res) => {
  const keys = await redisClient.keys('listing:us-*');
  const listings = [];
  
  for (const key of keys) {
    const listing = await redisClient.hGetAll(key);
    const listingId = key.split(':')[1];
    const availability = await redisClient.get(`availability:${listingId}`);
    listings.push({ ...listing, availability, id: listingId });
  }
  
  res.json({ region: REGION, listings, latency: Math.random() * 50 + 30 });
});

// Optimistic booking with timestamp-based conflict resolution
app.post('/book', async (req, res) => {
  const { listingId, userId, timestamp } = req.body;
  const startTime = Date.now();
  
  const availability = await redisClient.get(`availability:${listingId}`);
  
  if (availability === 'available') {
    // Hold booking with timestamp
    const holdKey = `hold:${listingId}`;
    const existingHold = await redisClient.get(holdKey);
    
    if (existingHold) {
      const existing = JSON.parse(existingHold);
      // Conflict! Earliest timestamp wins
      if (timestamp < existing.timestamp) {
        await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
        setTimeout(async () => {
          await redisClient.set(`availability:${listingId}`, 'confirmed');
          await redisClient.del(holdKey);
          // Replicate to other regions
          await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
        }, 1000);
        
        res.json({
          success: true,
          message: 'Booking confirmed (won conflict resolution)',
          listingId,
          region: REGION,
          latency: Date.now() - startTime
        });
      } else {
        res.json({
          success: false,
          message: 'Booking conflict - another user reserved first',
          alternative: 'us-2',
          latency: Date.now() - startTime
        });
      }
    } else {
      await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
      setTimeout(async () => {
        await redisClient.set(`availability:${listingId}`, 'confirmed');
        await redisClient.del(holdKey);
        await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
      }, 1000);
      
      res.json({
        success: true,
        message: 'Booking confirmed',
        listingId,
        region: REGION,
        latency: Date.now() - startTime
      });
    }
  } else {
    res.json({
      success: false,
      message: 'Listing not available',
      alternative: 'us-3',
      latency: Date.now() - startTime
    });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', region: REGION }));

initRedis().then(() => {
  app.listen(PORT, () => console.log(`US Region Service running on port ${PORT}`));
});
