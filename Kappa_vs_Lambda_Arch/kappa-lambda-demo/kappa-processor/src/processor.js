import { Kafka } from 'kafkajs';
import express from 'express';

const kafka = new Kafka({
  clientId: 'kappa-processor',
  brokers: ['kafka:9092']
});

const consumer = kafka.consumer({ groupId: 'kappa-group' });
const app = express();

let kappaStats = {
  totalEvents: 0,
  pageViews: {},
  deviceBreakdown: {},
  avgSessionDuration: 0,
  lastEventTime: null,
  runningDurationSum: 0,
  replayMode: false,
  processorVersion: 'v1.0'
};

// Start HTTP server first so /health and /replay are available before consumer.run() (which never returns)
app.post('/replay', (req, res) => {
  kappaStats = {
    totalEvents: 0,
    pageViews: {},
    deviceBreakdown: {},
    avgSessionDuration: 0,
    lastEventTime: null,
    runningDurationSum: 0,
    replayMode: true,
    processorVersion: 'v1.1'
  };
  res.json({ message: 'Replay started', version: 'v1.1' });
  setTimeout(() => { kappaStats.replayMode = false; }, 5000);
});
app.get('/stats', (req, res) => res.json({ architecture: 'kappa', ...kappaStats }));
app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.listen(3004, () => console.log('Kappa Processor API on :3004'));

async function start() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'clickstream', fromBeginning: true });
  console.log('🔄 Kappa Processor started (unified stream processing)');
  await consumer.run({
    eachMessage: async ({ message }) => {
      const event = JSON.parse(message.value.toString());
      kappaStats.totalEvents++;
      kappaStats.runningDurationSum += event.sessionDuration;
      kappaStats.avgSessionDuration = Math.round(
        (kappaStats.runningDurationSum / kappaStats.totalEvents) * 100
      ) / 100;
      kappaStats.pageViews[event.page] = (kappaStats.pageViews[event.page] || 0) + 1;
      kappaStats.deviceBreakdown[event.device] = (kappaStats.deviceBreakdown[event.device] || 0) + 1;
      kappaStats.lastEventTime = event.timestamp;
    }
  });
}

start().catch(console.error);
