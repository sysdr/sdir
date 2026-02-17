'use strict';

const express   = require('express');
const Redis     = require('ioredis');
const WebSocket = require('ws');
const http      = require('http');
const path      = require('path');
const { v4: uuidv4 } = require('uuid');

const app    = express();
const server = http.createServer(app);
const wss    = new WebSocket.Server({ server });

const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: 6379,
  retryStrategy: (times) => Math.min(times * 100, 3000),
  lazyConnect: false
});

redis.on('error', (err) => console.error('[Redis]', err.message));

// ─── Tenant Tier Configuration ────────────────────────────────
// Each tier defines: ratePerSecond (sustained) + burst capacity
const TIERS = {
  'tenant-free':       { label: 'Free',       rate: 10,  burst: 20,   color: '#64748b', bgColor: '#f8fafc' },
  'tenant-pro':        { label: 'Pro',        rate: 100, burst: 200,  color: '#2563eb', bgColor: '#eff6ff' },
  'tenant-enterprise': { label: 'Enterprise', rate: 500, burst: 1000, color: '#7c3aed', bgColor: '#f5f3ff' }
};

// ─── In-Memory Stats ─────────────────────────────────────────
const stats = {};
for (const id of Object.keys(TIERS)) {
  stats[id] = {
    allowed: 0,
    throttled: 0,
    recentAllowed: [],   // timestamps for per-second rate calc
    recentThrottled: [],
    events: []           // recent event log (last 50)
  };
}

// ─── Token Bucket Lua Script (atomic read-modify-write) ──────
// KEYS[1] = redis key for this tenant's bucket
// ARGV[1] = rate (tokens/second), ARGV[2] = burst, ARGV[3] = now (ms)
const TOKEN_BUCKET_LUA = `
local key       = KEYS[1]
local rate      = tonumber(ARGV[1])
local burst     = tonumber(ARGV[2])
local now       = tonumber(ARGV[3])

local data      = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens    = tonumber(data[1])
local last_ts   = tonumber(data[2])

if tokens == nil then
  tokens  = burst
  last_ts = now
end

-- Refill based on elapsed time
local elapsed   = math.max(0, (now - last_ts) / 1000)
local refill    = elapsed * rate
tokens = math.min(burst, tokens + refill)

local granted = 0
if tokens >= 1 then
  tokens  = tokens - 1
  granted = 1
end

redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
redis.call('EXPIRE', key, 120)

-- Return [granted, remaining_tokens_floor]
return { granted, math.floor(tokens) }
`;

// ─── Middleware ───────────────────────────────────────────────
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ─── Rate-Limited Endpoint ───────────────────────────────────
app.get('/api/data', async (req, res) => {
  const tenantId = req.query.tenant;
  if (!tenantId || !TIERS[tenantId]) {
    return res.status(400).json({ error: 'Unknown or missing tenant param', validTenants: Object.keys(TIERS) });
  }

  const cfg = TIERS[tenantId];
  const key = `ratelimit:${tenantId}`;
  const now = Date.now();
  const st  = stats[tenantId];

  let granted, remaining;
  try {
    const result = await redis.eval(TOKEN_BUCKET_LUA, 1, key, cfg.rate, cfg.burst, now);
    granted   = result[0];
    remaining = result[1];
  } catch (e) {
    console.error('[Redis eval]', e.message);
    return res.status(500).json({ error: 'Rate limiter unavailable' });
  }

  // Update sliding window for rate display
  const cutoff = now - 1000;
  if (granted) {
    st.allowed++;
    st.recentAllowed.push(now);
    st.recentAllowed = st.recentAllowed.filter(t => t > cutoff);
  } else {
    st.throttled++;
    st.recentThrottled.push(now);
    st.recentThrottled = st.recentThrottled.filter(t => t > cutoff);
  }

  // Append to event log (keep last 40)
  st.events.unshift({
    id: uuidv4().slice(0,8),
    ts: now,
    status: granted ? 'ALLOW' : 'THROTTLE',
    remaining,
    endpoint: '/api/data'
  });
  if (st.events.length > 40) st.events.length = 40;

  broadcastMetrics();

  if (granted) {
    return res.json({
      status: 'ok',
      tenant: tenantId,
      tier: cfg.label,
      tokensRemaining: remaining,
      message: 'Request processed'
    });
  } else {
    const retryAfterMs = Math.ceil(1000 / cfg.rate);
    res.setHeader('Retry-After',             retryAfterMs);
    res.setHeader('X-RateLimit-Limit',       cfg.rate);
    res.setHeader('X-RateLimit-Remaining',   0);
    res.setHeader('X-RateLimit-Reset',       Math.ceil((now + retryAfterMs) / 1000));
    res.setHeader('X-Quota-Tier',            cfg.label.toUpperCase());
    return res.status(429).json({
      status: 'throttled',
      tenant: tenantId,
      tier: cfg.label,
      tokensRemaining: 0,
      retryAfterMs,
      message: 'Rate limit exceeded — noisy neighbor protection active'
    });
  }
});

// ─── Metrics Endpoint ────────────────────────────────────────
app.get('/metrics', (req, res) => {
  res.json(buildMetrics());
});

app.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

function buildMetrics() {
  const now = Date.now();
  const cutoff = now - 1000;
  const out = {};
  for (const [id, cfg] of Object.entries(TIERS)) {
    const st = stats[id];
    const total = st.allowed + st.throttled;
    const recent = st.recentAllowed.filter(t => t > cutoff).length
                 + st.recentThrottled.filter(t => t > cutoff).length;
    out[id] = {
      tier:         cfg.label,
      rate:         cfg.rate,
      burst:        cfg.burst,
      color:        cfg.color,
      bgColor:      cfg.bgColor,
      allowed:      st.allowed,
      throttled:    st.throttled,
      throttleRate: total > 0 ? Math.round((st.throttled / total) * 100) : 0,
      currentRps:   recent,
      events:       st.events.slice(0, 12)
    };
  }
  return out;
}

// ─── WebSocket Broadcast ──────────────────────────────────────
function broadcastMetrics() {
  if (wss.clients.size === 0) return;
  const payload = JSON.stringify({ type: 'metrics', data: buildMetrics(), ts: Date.now() });
  wss.clients.forEach(c => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'metrics', data: buildMetrics(), ts: Date.now() }));
});

setInterval(broadcastMetrics, 400);

// ─── Start ────────────────────────────────────────────────────
const PORT = process.env.PORT || 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`[API] Noisy Neighbor demo running on :${PORT}`);
  console.log('[API] Tenants:', Object.keys(TIERS).join(', '));
});
