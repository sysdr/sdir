import { Kafka } from 'kafkajs';
import express from 'express';
import cors from 'cors';

const kafka = new Kafka({
  clientId: 'stream-processor',
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092'],
  retry: {
    retries: 10,
    initialRetryTime: 300
  }
});

const consumer = kafka.consumer({ groupId: 'processor-group' });
const producer = kafka.producer();

const WINDOW_SIZE = 5000; // 5 second tumbling window
const LATE_ARRIVAL_GRACE = 3000; // 3 second grace period

let windowedCounts = new Map();
let currentWindowStart = Date.now();
let totalClicks = 0;
let lateEvents = 0;
let latestMetrics = {
  clicksPerSecond: 0,
  totalClicks: 0,
  lateEvents: 0,
  currentWindow: new Date().toISOString(),
  userActivity: {}
};

function processWindow() {
  const windowEnd = currentWindowStart + WINDOW_SIZE;
  const clicksInWindow = windowedCounts.size;
  const clicksPerSecond = (clicksInWindow / (WINDOW_SIZE / 1000)).toFixed(2);

  latestMetrics = {
    clicksPerSecond: parseFloat(clicksPerSecond),
    totalClicks,
    lateEvents,
    currentWindow: new Date(currentWindowStart).toISOString(),
    userActivity: Object.fromEntries(windowedCounts)
  };

  console.log(`📊 Window [${new Date(currentWindowStart).toISOString()}]: ${clicksInWindow} clicks, ${clicksPerSecond} clicks/sec`);
  
  // Clear old window data
  windowedCounts.clear();
  currentWindowStart = Date.now();
}

async function processEvents() {
  await consumer.connect();
  await producer.connect();
  await consumer.subscribe({ topic: 'user-clicks', fromBeginning: false });

  console.log('✓ Stream processor started');

  // Process windows every 5 seconds
  setInterval(processWindow, WINDOW_SIZE);

  await consumer.run({
    eachMessage: async ({ message }) => {
      const event = JSON.parse(message.value.toString());
      const eventTime = event.timestamp;
      const processingTime = Date.now();

      // Check if event is within current window
      const isInCurrentWindow = eventTime >= currentWindowStart && 
                                eventTime < (currentWindowStart + WINDOW_SIZE);
      
      // Check if event is within grace period of previous window
      const isWithinGrace = eventTime >= (currentWindowStart - LATE_ARRIVAL_GRACE) && 
                           eventTime < currentWindowStart;

      if (isInCurrentWindow) {
        const count = windowedCounts.get(event.userId) || 0;
        windowedCounts.set(event.userId, count + 1);
        totalClicks++;
      } else if (isWithinGrace) {
        // Process late event (allowed lateness)
        console.log(`⚠️  Late event processed: ${event.userId} (${processingTime - eventTime}ms late)`);
        const count = windowedCounts.get(event.userId) || 0;
        windowedCounts.set(event.userId, count + 1);
        totalClicks++;
        lateEvents++;
      } else {
        // Too late, drop the event
        console.log(`❌ Event dropped (too late): ${event.userId}`);
      }
    }
  });
}

// HTTP API for dashboard
const app = express();
app.use(cors({
  origin: ['http://localhost:3000', 'http://127.0.0.1:3000'],
  credentials: true
}));

app.get('/metrics', (req, res) => {
  res.json(latestMetrics);
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(8080, '0.0.0.0', () => {
  console.log('✓ HTTP API listening on :8080');
});

processEvents().catch(console.error);
