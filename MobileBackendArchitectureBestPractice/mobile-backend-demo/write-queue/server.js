import express from 'express';
import Redis from 'ioredis';

const app = express();
app.use(express.json());

const redis = new Redis(process.env.REDIS_URL);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'write-queue' });
});

app.get('/queue/status', async (req, res) => {
  const size = await redis.llen('write_queue');
  const metrics = {
    syncRequests: await redis.get('metrics:sync_requests') || 0,
    writesQueued: await redis.get('metrics:writes_queued') || 0,
    conflicts: await redis.get('metrics:conflicts') || 0
  };

  res.json({ queueSize: size, metrics });
});

app.listen(3002, () => {
  console.log('✅ Write Queue Service running on port 3002');
});
