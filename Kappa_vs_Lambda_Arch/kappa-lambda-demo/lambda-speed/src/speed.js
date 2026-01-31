import { Kafka } from 'kafkajs';
import express from 'express';

const kafka = new Kafka({
  clientId: 'lambda-speed',
  brokers: ['kafka:9092']
});

const consumer = kafka.consumer({ groupId: 'lambda-speed-group' });
const app = express();

let speedStats = {
  totalEvents: 0,
  pageViews: {},
  deviceBreakdown: {},
  avgSessionDuration: 0,
  lastEventTime: null,
  runningDurationSum: 0
};

async function start() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'clickstream', fromBeginning: false });

  console.log('⚡ Lambda Speed Layer started');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const event = JSON.parse(message.value.toString());
      
      speedStats.totalEvents++;
      speedStats.runningDurationSum += event.sessionDuration;
      
      // Round to 1 decimal (different from batch layer)
      speedStats.avgSessionDuration = Math.round(
        (speedStats.runningDurationSum / speedStats.totalEvents) * 10
      ) / 10;

      speedStats.pageViews[event.page] = (speedStats.pageViews[event.page] || 0) + 1;
      speedStats.deviceBreakdown[event.device] = (speedStats.deviceBreakdown[event.device] || 0) + 1;
      speedStats.lastEventTime = event.timestamp;
    }
  });

  app.get('/stats', (req, res) => res.json({ 
    layer: 'speed',
    ...speedStats 
  }));
  app.get('/health', (req, res) => res.json({ status: 'ok' }));
  app.listen(3003, () => console.log('Speed Layer API on :3003'));
}

start().catch(console.error);
