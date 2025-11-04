const { Kafka } = require('kafkajs');
const { createClient } = require('redis');

const kafka = new Kafka({
  clientId: 'stream-processor',
  brokers: [process.env.KAFKA_BOOTSTRAP_SERVERS]
});

const consumer = kafka.consumer({ groupId: 'stream-processing-group' });
const redis = createClient({ url: process.env.REDIS_URL });

// Real-time aggregations
const metrics = {
  totalEvents: 0,
  eventsByType: {},
  revenueBySegment: {},
  activeUsers: new Set(),
  hourlyMetrics: {},
  eventsPerMinute: [] // Rolling window of last 20 minutes
};

async function processEvent(event) {
  const data = JSON.parse(event.value.toString());
  
  // Update real-time metrics
  metrics.totalEvents++;
  metrics.eventsByType[data.eventType] = (metrics.eventsByType[data.eventType] || 0) + 1;
  metrics.activeUsers.add(data.userId);
  
  if (data.eventType === 'purchase') {
    const segment = data.userSegment;
    metrics.revenueBySegment[segment] = (metrics.revenueBySegment[segment] || 0) + data.amount;
  }
  
  // Hourly aggregation
  const hour = new Date(data.timestamp).getHours();
  if (!metrics.hourlyMetrics[hour]) {
    metrics.hourlyMetrics[hour] = { events: 0, revenue: 0 };
  }
  metrics.hourlyMetrics[hour].events++;
  if (data.eventType === 'purchase') {
    metrics.hourlyMetrics[hour].revenue += data.amount;
  }
  
  // Per-minute aggregation for real-time chart
  const now = new Date();
  const minuteKey = `${now.getHours()}:${String(now.getMinutes()).padStart(2, '0')}`;
  const minuteIndex = metrics.eventsPerMinute.findIndex(m => m.time === minuteKey);
  
  if (minuteIndex >= 0) {
    metrics.eventsPerMinute[minuteIndex].count++;
  } else {
    metrics.eventsPerMinute.push({ time: minuteKey, count: 1 });
    // Keep only last 20 minutes
    if (metrics.eventsPerMinute.length > 20) {
      metrics.eventsPerMinute.shift();
    }
  }
  
  // Store in Redis for real-time access
  await redis.hSet('realtime:metrics', {
    totalEvents: metrics.totalEvents,
    activeUsers: metrics.activeUsers.size,
    eventsByType: JSON.stringify(metrics.eventsByType),
    revenueBySegment: JSON.stringify(metrics.revenueBySegment),
    hourlyMetrics: JSON.stringify(metrics.hourlyMetrics),
    eventsPerMinute: JSON.stringify(metrics.eventsPerMinute)
  });
  
  // Store recent events for debugging
  await redis.lPush('recent:events', JSON.stringify(data));
  await redis.lTrim('recent:events', 0, 99); // Keep last 100 events
  
  console.log(`Processed ${data.eventType} - Total: ${metrics.totalEvents}, Active Users: ${metrics.activeUsers.size}`);
}

async function startProcessor() {
  await redis.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'user-events' });
  
  console.log('⚡ Stream processor started (Kappa Pattern)...');
  
  await consumer.run({
    eachMessage: async ({ message }) => {
      await processEvent(message);
    }
  });
}

startProcessor().catch(console.error);
