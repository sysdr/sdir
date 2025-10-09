const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

let redisClient;
let eventStormActive = false;

// Anti-pattern: Event Storm Generator
app.post('/trigger-event-storm', async (req, res) => {
  eventStormActive = true;
  const { orderId } = req.body;
  
  // This demonstrates the anti-pattern of event storms
  // One event triggers multiple other events recursively
  
  for (let i = 0; i < 10; i++) {
    await redisClient.xAdd('storm-events', '*', {
      eventType: 'EventStormTrigger',
      data: JSON.stringify({ orderId, iteration: i })
    });
  }
  
  res.json({ message: 'Event storm triggered!', orderId });
});

app.post('/stop-event-storm', (req, res) => {
  eventStormActive = false;
  res.json({ message: 'Event storm stopped' });
});

// Anti-pattern event processor that creates more events
async function processStormEvents() {
  if (!eventStormActive) return;
  
  try {
    const events = await redisClient.xRead(
      { key: 'storm-events', id: '$' },
      { BLOCK: 100 }
    );
    
    if (events) {
      for (const event of events[0].messages) {
        const data = JSON.parse(event.message.data);
        
        // Anti-pattern: Each event triggers 3 more events
        for (let i = 0; i < 3; i++) {
          await redisClient.xAdd('storm-events', '*', {
            eventType: 'CascadingEvent',
            data: JSON.stringify({ 
              parent: data.orderId, 
              cascade: i,
              level: (data.level || 0) + 1
            })
          });
        }
      }
    }
  } catch (error) {
    console.error('Storm processing error:', error);
  }
  
  if (eventStormActive) {
    setTimeout(processStormEvents, 50);
  }
}

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'antipattern' }));

async function init() {
  redisClient = createClient({ url: process.env.REDIS_URL });
  await redisClient.connect();
  console.log('Anti-pattern Service started on port 3006');
}

app.listen(3006, init);
