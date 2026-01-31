import express from 'express';
import cors from 'cors';
import fetch from 'node-fetch';

const app = express();
app.use(cors());

async function fetchStats(url) {
  try {
    const res = await fetch(url);
    return await res.json();
  } catch (err) {
    return null;
  }
}

app.get('/lambda/merged', async (req, res) => {
  const [batch, speed] = await Promise.all([
    fetchStats('http://lambda-batch:3002/stats'),
    fetchStats('http://lambda-speed:3003/stats')
  ]);

  if (!batch || !speed) {
    return res.json({ error: 'Layer unavailable' });
  }

  // Merge with detection of inconsistencies
  const merged = {
    totalEvents: batch.totalEvents + speed.totalEvents,
    avgSessionDuration: {
      batch: batch.avgSessionDuration,
      speed: speed.avgSessionDuration,
      drift: Math.abs(batch.avgSessionDuration - speed.avgSessionDuration)
    },
    pageViews: { ...batch.pageViews, ...speed.pageViews },
    deviceBreakdown: { ...batch.deviceBreakdown, ...speed.deviceBreakdown }
  };

  res.json(merged);
});

app.get('/kappa/stats', async (req, res) => {
  const stats = await fetchStats('http://kappa-processor:3004/stats');
  res.json(stats || { error: 'Kappa unavailable' });
});

app.post('/replay', async (req, res) => {
  try {
    const r = await fetch('http://kappa-processor:3004/replay', { method: 'POST' });
    const data = await r.json().catch(() => ({}));
    res.status(r.status).json(r.ok ? data : { error: data.error || 'Replay failed' });
  } catch (err) {
    res.status(502).json({ error: 'Kappa processor unavailable' });
  }
});

app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.listen(3005, () => console.log('Serving Layer on :3005'));
