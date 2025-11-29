import express from 'express';
import Redis from 'ioredis';
import pkg from 'pg';

const { Pool } = pkg;
const app = express();
app.use(express.json());

const redis = new Redis(process.env.REDIS_URL);
const pool = new Pool({ connectionString: process.env.POSTGRES_URL });

// Process write queue continuously
async function processWriteQueue() {
  while (true) {
    try {
      const item = await redis.brpop('write_queue', 5);
      if (!item) continue;

      const write = JSON.parse(item[1]);
      await processWrite(write);
    } catch (error) {
      console.error('Queue processing error:', error);
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

async function processWrite(write) {
  const { deviceId, key, value, vectorClock, timestamp } = write;

  // Check for conflicts using vector clocks
  const existing = await pool.query(
    'SELECT vector_clock, version FROM sync_data WHERE device_id = $1 AND data_key = $2',
    [deviceId, key]
  );

  let hasConflict = false;
  let newVersion = 1;

  if (existing.rows.length > 0) {
    const existingClock = existing.rows[0].vector_clock || {};
    hasConflict = detectConflict(existingClock, vectorClock);
    newVersion = existing.rows[0].version + 1;

    if (hasConflict) {
      await redis.incr('metrics:conflicts');
      console.log(`⚠️  Conflict detected for ${deviceId}:${key}`);
    }
  }

  // Merge vector clocks
  const mergedClock = { ...vectorClock };
  mergedClock[deviceId] = (mergedClock[deviceId] || 0) + 1;

  // Write to database
  await pool.query(`
    INSERT INTO sync_data (device_id, data_key, data_value, version, vector_clock)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (device_id, data_key) 
    DO UPDATE SET 
      data_value = $3,
      version = sync_data.version + 1,
      vector_clock = $5,
      updated_at = CURRENT_TIMESTAMP
  `, [deviceId, key, value, newVersion, JSON.stringify(mergedClock)]);

  console.log(`✅ Synced: ${deviceId}:${key} (v${newVersion})`);
}

function detectConflict(clock1, clock2) {
  const allKeys = new Set([...Object.keys(clock1), ...Object.keys(clock2)]);
  
  let clock1Ahead = false;
  let clock2Ahead = false;

  for (const key of allKeys) {
    const v1 = clock1[key] || 0;
    const v2 = clock2[key] || 0;
    
    if (v1 > v2) clock1Ahead = true;
    if (v2 > v1) clock2Ahead = true;
  }

  return clock1Ahead && clock2Ahead;
}

// Delta sync endpoint
app.post('/sync/delta', async (req, res) => {
  const { deviceId, since } = req.body;

  const result = await pool.query(
    `SELECT * FROM sync_data WHERE device_id = $1 AND updated_at > $2 ORDER BY updated_at`,
    [deviceId, since || '1970-01-01']
  );

  res.json({ delta: result.rows, count: result.rows.length });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'sync-service' });
});

processWriteQueue();

app.listen(3001, () => {
  console.log('✅ Sync Service running on port 3001');
});
