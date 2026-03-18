import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';
import { createClient } from 'redis';
import { v4 as uuidv4 } from 'uuid';
import { SYSTEM_PROMPT, FEW_SHOT_EXAMPLES } from '../config/prompts.js';
import { buildAnthropicRequest, parseUsage, computeCost } from './anthropic.js';

const app = express();
app.use(cors());
app.use(express.json());

// ── Redis ──────────────────────────────────────────────────
const redis = createClient({ url: process.env.REDIS_URL || 'redis://redis:6379' });
redis.on('error', (err) => console.error('[redis]', err.message));
await redis.connect();
console.log('[redis] connected');

// Metric helpers
const incrMetric = (key, by = 1) => redis.incrByFloat(key, by);
const getMetrics = async () => {
  const keys = [
    'metrics:requests_total', 'metrics:cache_hit_tokens',
    'metrics:cache_miss_tokens', 'metrics:total_cost_cached',
    'metrics:total_cost_uncached', 'metrics:latency_cached_sum',
    'metrics:latency_uncached_sum', 'metrics:latency_cached_count',
    'metrics:latency_uncached_count'
  ];
  const vals = await redis.mGet(keys);
  return Object.fromEntries(keys.map((k, i) => [k.replace('metrics:', ''), parseFloat(vals[i] || 0)]));
};

// ── WebSocket broadcast ────────────────────────────────────
const server = createServer(app);
const wss = new WebSocketServer({ server });
const broadcast = (data) => {
  const msg = JSON.stringify(data);
  wss.clients.forEach(c => c.readyState === 1 && c.send(msg));
};

// ── Routes ─────────────────────────────────────────────────

// Health
app.get('/health', (_, res) => res.json({ status: 'ok' }));

// Mock response when API key is missing/invalid or DEMO_MOCK=true (dashboard works without Anthropic credits)
function useMockMode() {
  const key = (process.env.ANTHROPIC_API_KEY || '').trim();
  if (process.env.DEMO_MOCK === 'true' || process.env.DEMO_MOCK === '1') return true;
  if (!key || !key.startsWith('sk-ant-') || key.includes('placeholder')) return true;
  return false;
}

// Simulated usage for mock: cached shows cache read after first request; uncached always full input
let mockCacheWarmed = false;
function getMockUsage(useCache) {
  if (useCache) {
    if (!mockCacheWarmed) {
      mockCacheWarmed = true;
      return { cacheWriteTokens: 1520, cacheReadTokens: 0, inputTokens: 80, outputTokens: 180 };
    }
    return { cacheWriteTokens: 0, cacheReadTokens: 1520, inputTokens: 80, outputTokens: 180 };
  }
  return { cacheWriteTokens: 0, cacheReadTokens: 0, inputTokens: 1600, outputTokens: 180 };
}

// Pre-written answers for demo (no Anthropic API required)
const DEMO_ANSWERS = {
  'write amplification': 'Write amplification in LSM trees is the ratio of physical bytes written to storage versus logical bytes written by the application. It arises from compaction: data written once to the top level (L0) is rewritten during each merge pass as it moves down levels. With a size ratio of 10 and multiple levels, a single user write can be physically written many times before reaching the bottom level. Leveled compaction (e.g. RocksDB default) trades more compaction I/O for better read performance; tiered compaction reduces write amplification but increases read amplification.',
  'split-brain': 'Split-brain in distributed databases occurs when a network partition causes two or more subsets of nodes to each believe they are the only active group. Each partition may elect its own leader and accept writes, leading to conflicting data when the partition heals. Mitigations include quorum-based writes, fencing tokens, and consensus (e.g. Raft, Paxos) so only a majority partition can make progress. Detection is done via heartbeats and timeouts; resolution often requires manual intervention or last-writer-wins with version vectors.',
  'consistent hashing': 'Consistent hashing handles node additions (and removals) by mapping both keys and nodes to a ring. When a node is added, only the keys that fall between its predecessor and the new node on the ring are reassigned to it; the rest stay on the same nodes. That minimizes key movement. Virtual nodes (vnodes) give each physical node multiple points on the ring for better load balance. Node addition is O(K/N) keys moved on average where K is total keys and N is number of nodes.',
  'read-through and write-through': 'Read-through cache: on a miss, the cache layer loads the value from the backing store, caches it, and returns it to the client. Write-through: writes go to both the cache and the backing store so the store is always up to date; reads can always hit cache or load from store. Write-through keeps cache and store consistent but adds write latency. Read-through simplifies reads but can cause stale reads if the store is updated elsewhere. Write-behind (write-back) improves write latency by batching updates to the store but risks loss on cache failure.'
};

function getMockAnswer(question, useCache) {
  const q = (question || '').toLowerCase();
  for (const [key, answer] of Object.entries(DEMO_ANSWERS)) {
    if (q.includes(key)) return answer;
  }
  return 'Prompt caching reduces cost and latency by reusing the KV cache for repeated prompt prefixes (e.g. system prompt + few-shot examples). Cached reads are billed at a fraction of normal input price; the first request pays a one-time cache write cost. This demo shows the token and cost difference between cached and uncached requests.';
}

// Single query — toggle caching with ?cached=true|false
app.post('/api/query', async (req, res) => {
  const { question, useCache = true } = req.body;
  if (!question?.trim()) return res.status(400).json({ error: 'question required' });

  const reqId = uuidv4().slice(0, 8);
  const t0 = Date.now();

  const apiKey = (process.env.ANTHROPIC_API_KEY || '').trim();
  const isMock = useMockMode();

  try {
    let usage, cost, answer;

    if (isMock) {
      // Simulate latency: cached faster than uncached
      const latencyMs = useCache ? 520 + Math.random() * 200 : 1600 + Math.random() * 400;
      await new Promise(r => setTimeout(r, Math.min(latencyMs, 100)));
      usage = getMockUsage(useCache);
      cost = computeCost(usage, useCache);
      answer = getMockAnswer(question, useCache);
      const actualLatency = Date.now() - t0;
      // Persist metrics (same as real path)
      const cacheLabel = useCache ? 'cached' : 'uncached';
      await Promise.all([
        incrMetric('metrics:requests_total'),
        incrMetric('metrics:cache_hit_tokens', usage.cacheReadTokens),
        incrMetric('metrics:cache_miss_tokens', usage.cacheWriteTokens + usage.inputTokens),
        incrMetric(`metrics:total_cost_${cacheLabel}`, cost.total),
        incrMetric(`metrics:latency_${cacheLabel}_sum`, actualLatency),
        incrMetric(`metrics:latency_${cacheLabel}_count`, 1)
      ]);
      const metrics = await getMetrics();
      const result = { reqId, latencyMs: actualLatency, useCache, usage, cost, answer, metrics };
      broadcast({ type: 'query_result', ...result });
      return res.json(result);
    }

    // Real API call
    const raw = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'prompt-caching-2024-07-31'
      },
      body: JSON.stringify(buildAnthropicRequest(question, useCache, FEW_SHOT_EXAMPLES, SYSTEM_PROMPT).payload)
    });

    if (!raw.ok) {
      let errMsg = raw.statusText;
      try {
        const errBody = await raw.json();
        errMsg = errBody.error?.message || errBody.message || errBody.error || errMsg;
      } catch (_) {
        const text = await raw.text();
        if (text) errMsg = text.slice(0, 200);
      }
      // Fall back to mock if API fails (e.g. low credits) so dashboard still updates
      if (errMsg.includes('credit') || errMsg.includes('balance') || errMsg.includes('billing')) {
        const latencyMs = useCache ? 520 + Math.random() * 200 : 1600 + Math.random() * 400;
        await new Promise(r => setTimeout(r, 50));
        const mockUsage = getMockUsage(useCache);
        const mockCost = computeCost(mockUsage, useCache);
        const cacheLabel = useCache ? 'cached' : 'uncached';
        await Promise.all([
          incrMetric('metrics:requests_total'),
          incrMetric('metrics:cache_hit_tokens', mockUsage.cacheReadTokens),
          incrMetric('metrics:cache_miss_tokens', mockUsage.cacheWriteTokens + mockUsage.inputTokens),
          incrMetric(`metrics:total_cost_${cacheLabel}`, mockCost.total),
          incrMetric(`metrics:latency_${cacheLabel}_sum`, latencyMs),
          incrMetric(`metrics:latency_${cacheLabel}_count`, 1)
        ]);
        const metrics = await getMetrics();
        const result = {
          reqId,
          latencyMs,
          useCache,
          usage: mockUsage,
          cost: mockCost,
          answer: getMockAnswer(question, useCache) + '\n(API: ' + errMsg + ')',
          metrics
        };
        broadcast({ type: 'query_result', ...result });
        return res.json(result);
      }
      throw new Error(errMsg);
    }

    const data = await raw.json();
    const latencyMs = Date.now() - t0;
    usage = parseUsage(data.usage || {});
    cost = computeCost(usage, useCache);
    answer = (data.content && data.content[0] && data.content[0].text) ? String(data.content[0].text) : '';

    const cacheLabel = useCache ? 'cached' : 'uncached';
    await Promise.all([
      incrMetric('metrics:requests_total'),
      incrMetric('metrics:cache_hit_tokens', usage.cacheReadTokens),
      incrMetric('metrics:cache_miss_tokens', usage.cacheWriteTokens + usage.inputTokens),
      incrMetric(`metrics:total_cost_${cacheLabel}`, cost.total),
      incrMetric(`metrics:latency_${cacheLabel}_sum`, latencyMs),
      incrMetric(`metrics:latency_${cacheLabel}_count`, 1)
    ]);

    const metrics = await getMetrics();
    const result = { reqId, latencyMs, useCache, usage, cost, answer, metrics };
    broadcast({ type: 'query_result', ...result });
    res.json(result);

  } catch (err) {
    console.error('[query error]', err.message);
    if (!res.headersSent) {
      res.status(500).json({ error: err.message || 'Request failed' });
    }
  }
});

// Batch comparison — runs same question with and without caching
app.post('/api/compare', async (req, res) => {
  const { question } = req.body;
  if (!question?.trim()) return res.status(400).json({ error: 'question required' });

  try {
    // Fire both in parallel
    const [cachedResp, uncachedResp] = await Promise.all([
      fetch(`http://localhost:${PORT}/api/query`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question, useCache: true })
      }),
      fetch(`http://localhost:${PORT}/api/query`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question, useCache: false })
      })
    ]);
    const [cached, uncached] = await Promise.all([cachedResp.json(), uncachedResp.json()]);
    if (!cachedResp.ok && cached?.error) {
      return res.status(cachedResp.status).json({ error: cached.error });
    }
    if (!uncachedResp.ok && uncached?.error) {
      return res.status(uncachedResp.status).json({ error: uncached.error });
    }
    res.json({ cached, uncached });
  } catch (err) {
    if (!res.headersSent) res.status(500).json({ error: err.message || 'Compare failed' });
  }
});

// Current metrics snapshot
app.get('/api/metrics', async (_, res) => {
  const m = await getMetrics();
  const cachedCount = m.latency_cached_count || 0;
  const uncachedCount = m.latency_uncached_count || 0;
  res.json({
    ...m,
    avg_latency_cached_ms: cachedCount > 0 ? Math.round(m.latency_cached_sum / cachedCount) : 0,
    avg_latency_uncached_ms: uncachedCount > 0 ? Math.round(m.latency_uncached_sum / uncachedCount) : 0,
    cost_savings_usd: Math.max(0, m.total_cost_uncached - m.total_cost_cached).toFixed(6),
    cache_hit_rate: m.requests_total > 0
      ? ((m.cache_hit_tokens / (m.cache_hit_tokens + m.cache_miss_tokens)) * 100).toFixed(1)
      : '0.0'
  });
});

// Reset metrics
app.delete('/api/metrics', async (_, res) => {
  const keys = await redis.keys('metrics:*');
  if (keys.length) await redis.del(keys);
  broadcast({ type: 'metrics_reset' });
  res.json({ cleared: keys.length });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => console.log(`[server] http://localhost:${PORT}`));
