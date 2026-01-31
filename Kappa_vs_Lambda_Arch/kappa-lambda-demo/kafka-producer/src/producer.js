import { Kafka } from 'kafkajs';
import express from 'express';

const kafka = new Kafka({
  clientId: 'clickstream-producer',
  brokers: ['kafka:9092']
});

const producer = kafka.producer();
const app = express();

const PAGES = ['home', 'products', 'cart', 'checkout', 'profile', 'search'];
const DEVICES = ['mobile', 'desktop', 'tablet'];
let eventCount = 0;

async function generateEvent() {
  const event = {
    eventId: ++eventCount,
    timestamp: new Date().toISOString(),
    userId: `user_${Math.floor(Math.random() * 1000)}`,
    page: PAGES[Math.floor(Math.random() * PAGES.length)],
    device: DEVICES[Math.floor(Math.random() * DEVICES.length)],
    sessionDuration: Math.floor(Math.random() * 300),
    clicks: Math.floor(Math.random() * 20)
  };

  await producer.send({
    topic: 'clickstream',
    messages: [{ value: JSON.stringify(event) }]
  });

  return event;
}

async function start() {
  await producer.connect();
  const admin = kafka.admin();
  await admin.connect();
  try {
    await admin.createTopics({ topics: [{ topic: 'clickstream', numPartitions: 1 }], validateOnly: false });
    console.log('📊 Topic clickstream ready');
  } catch (e) {
    if (e.type !== 'TOPIC_ALREADY_EXISTS' && !/already exists/i.test(String(e.message))) throw e;
  }
  await admin.disconnect();
  console.log('📊 Kafka Producer started');

  // Generate events every 500ms
  setInterval(async () => {
    try {
      await generateEvent();
    } catch (err) {
      console.error('Error producing event:', err);
    }
  }, 500);

  app.get('/health', (req, res) => res.json({ status: 'ok', events: eventCount }));
  app.listen(3001, () => console.log('Producer API on :3001'));
}

start().catch(console.error);
