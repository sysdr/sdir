const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');

const app = express();
app.use(cors());
app.use(express.json());

const REGION = 'EU';
const PORT = 3002;

let redisClient;

async function initRedis() {
  redisClient = createClient({ url: 'redis://redis:6379' });
  await redisClient.connect();
  
  const listings = [
    { id: 'eu-1', name: 'Paris Apartment', region: 'EU', price: 200 },
    { id: 'eu-2', name: 'London Flat', region: 'EU', price: 220 },
    { id: 'eu-3', name: 'Berlin Loft', region: 'EU', price: 150 }
  ];
  
  for (const listing of listings) {
    await redisClient.hSet(`listing:${listing.id}`, listing);
    await redisClient.set(`availability:${listing.id}`, 'available');
  }
}

app.get('/listings', async (req, res) => {
  const keys = await redisClient.keys('listing:eu-*');
  const listings = [];
  
  for (const key of keys) {
    const listing = await redisClient.hGetAll(key);
    const listingId = key.split(':')[1];
    const availability = await redisClient.get(`availability:${listingId}`);
    listings.push({ ...listing, availability, id: listingId });
  }
  
  res.json({ region: REGION, listings, latency: Math.random() * 50 + 40 });
});

app.post('/book', async (req, res) => {
  const { listingId, userId, timestamp } = req.body;
  const startTime = Date.now();
  
  const availability = await redisClient.get(`availability:${listingId}`);
  
  if (availability === 'available') {
    const holdKey = `hold:${listingId}`;
    const existingHold = await redisClient.get(holdKey);
    
    if (existingHold) {
      const existing = JSON.parse(existingHold);
      if (timestamp < existing.timestamp) {
        await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
        setTimeout(async () => {
          await redisClient.set(`availability:${listingId}`, 'confirmed');
          await redisClient.del(holdKey);
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
          alternative: 'eu-2',
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
      alternative: 'eu-3',
      latency: Date.now() - startTime
    });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', region: REGION }));

initRedis().then(() => {
  app.listen(PORT, () => console.log(`EU Region Service running on port ${PORT}`));
});
