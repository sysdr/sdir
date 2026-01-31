import { Kafka } from 'kafkajs';
import express from 'express';

const kafka = new Kafka({
  clientId: 'lambda-batch',
  brokers: ['kafka:9092']
});

const consumer = kafka.consumer({ groupId: 'lambda-batch-group' });
const app = express();

let batchBuffer = [];
let batchStats = {
  totalEvents: 0,
  pageViews: {},
  deviceBreakdown: {},
  avgSessionDuration: 0,
  lastBatchTime: null,
  batchCount: 0
};

async function processBatch() {
  if (batchBuffer.length === 0) return;

  const events = [...batchBuffer];
  batchBuffer = [];

  // Batch processing with intentional rounding differences
  const totalDuration = events.reduce((sum, e) => sum + e.sessionDuration, 0);
  
  batchStats.totalEvents += events.length;
  batchStats.batchCount++;
  
  // Round to 2 decimals (different from speed layer)
  batchStats.avgSessionDuration = Math.round(
    (totalDuration / events.length) * 100
  ) / 100;

  events.forEach(event => {
    batchStats.pageViews[event.page] = (batchStats.pageViews[event.page] || 0) + 1;
    batchStats.deviceBreakdown[event.device] = (batchStats.deviceBreakdown[event.device] || 0) + 1;
  });

  batchStats.lastBatchTime = new Date().toISOString();
  console.log(`✅ Batch ${batchStats.batchCount} processed: ${events.length} events`);
}

async function start() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'clickstream', fromBeginning: false });

  console.log('📦 Lambda Batch Layer started');

  // Process batch every 30 seconds
  setInterval(processBatch, 30000);

  await consumer.run({
    eachMessage: async ({ message }) => {
      const event = JSON.parse(message.value.toString());
      batchBuffer.push(event);
    }
  });

  app.get('/stats', (req, res) => res.json({ 
    layer: 'batch',
    ...batchStats 
  }));
  app.get('/health', (req, res) => res.json({ status: 'ok' }));
  app.listen(3002, () => console.log('Batch Layer API on :3002'));
}

start().catch(console.error);
