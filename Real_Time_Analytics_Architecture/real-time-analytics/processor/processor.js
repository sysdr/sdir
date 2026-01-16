const Redis = require('ioredis');

const redis = new Redis(process.env.REDIS_URL);
const STREAM_KEY = 'clickstream:events';
const CONSUMER_GROUP = 'analytics-processors';
const CONSUMER_NAME = `processor-${process.pid}`;

// HyperLogLog for unique user counting
const METRICS_PREFIX = 'metrics:';
const WINDOW_SIZE_MS = 60000; // 1 minute tumbling windows

async function initializeConsumerGroup() {
  try {
    await redis.xgroup('CREATE', STREAM_KEY, CONSUMER_GROUP, '0', 'MKSTREAM');
    console.log('Consumer group created');
  } catch (error) {
    if (!error.message.includes('BUSYGROUP')) {
      throw error;
    }
    console.log('Consumer group already exists');
  }
}

function getWindowKey(timestamp) {
  const windowStart = Math.floor(timestamp / WINDOW_SIZE_MS) * WINDOW_SIZE_MS;
  return windowStart;
}

async function processEvents() {
  while (true) {
    try {
      // Read from stream with blocking
      const results = await redis.xreadgroup(
        'GROUP', CONSUMER_GROUP, CONSUMER_NAME,
        'COUNT', 10,
        'BLOCK', 1000,
        'STREAMS', STREAM_KEY, '>'
      );

      if (!results) continue;

      for (const [stream, messages] of results) {
        for (const [messageId, fields] of messages) {
          const event = {};
          for (let i = 0; i < fields.length; i += 2) {
            event[fields[i]] = fields[i + 1];
          }

          const windowKey = getWindowKey(parseInt(event.timestamp));
          const windowMetricsKey = `${METRICS_PREFIX}window:${windowKey}`;

          // Increment total events counter
          await redis.hincrby(windowMetricsKey, 'total_events', 1);

          // Add unique user to HyperLogLog
          await redis.pfadd(`${windowMetricsKey}:unique_users`, event.userId);

          // Increment page view counter
          await redis.zincrby(`${windowMetricsKey}:top_pages`, 1, event.page);

          // Track session
          await redis.sadd(`${windowMetricsKey}:sessions`, event.sessionId);

          // Set expiry for old windows (keep 1 hour)
          await redis.expire(windowMetricsKey, 3600);
          await redis.expire(`${windowMetricsKey}:unique_users`, 3600);
          await redis.expire(`${windowMetricsKey}:top_pages`, 3600);
          await redis.expire(`${windowMetricsKey}:sessions`, 3600);

          // Update current window pointer
          await redis.set('metrics:current_window', windowKey, 'EX', 3600);

          // Acknowledge message
          await redis.xack(STREAM_KEY, CONSUMER_GROUP, messageId);
        }
      }
    } catch (error) {
      console.error('Processing error:', error);
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

async function main() {
  console.log('Starting real-time analytics processor...');
  await initializeConsumerGroup();
  console.log('Processing events...');
  await processEvents();
}

main().catch(console.error);
