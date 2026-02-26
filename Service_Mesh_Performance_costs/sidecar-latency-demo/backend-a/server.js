const express = require('express');
const http    = require('http');
const { v4: uuidv4 } = require('uuid');

const app  = express();
const PORT = process.env.PORT || 3001;

// Simulate variable processing time (1–15ms)
function simulateWork(min = 1, max = 15) {
  return new Promise(resolve => setTimeout(resolve, min + Math.random() * (max - min)));
}

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'backend-a' }));

app.get('/api/data', async (req, res) => {
  const start = Date.now();
  await simulateWork(1, 10);
  const appMs = Date.now() - start;
  res.json({
    requestId: uuidv4(),
    service:   'backend-a',
    appProcessingMs: appMs,
    timestamp: Date.now(),
    data: { value: Math.random() * 1000 }
  });
});

// Downstream call through sidecar proxy to backend-b
app.get('/api/chain', async (req, res) => {
  const reqStart = Date.now();
  await simulateWork(1, 5);

  // Call backend-b via envoy sidecar (direct)
  const targetHost = process.env.BACKEND_B_HOST || 'envoy-sidecar-b';
  const targetPort = process.env.BACKEND_B_PORT || 8082;

  const callStart = Date.now();
  const result = await new Promise((resolve, reject) => {
    const options = {
      hostname: targetHost,
      port: targetPort,
      path: '/api/data',
      method: 'GET',
      headers: { 'x-request-id': uuidv4(), 'x-protocol': req.query.protocol || 'http1' }
    };
    const r = http.request(options, resp => {
      let body = '';
      resp.on('data', chunk => body += chunk);
      resp.on('end', () => {
        try { resolve(JSON.parse(body)); } catch { resolve({ raw: body }); }
      });
    });
    r.on('error', reject);
    r.setTimeout(5000, () => { r.destroy(); reject(new Error('timeout')); });
    r.end();
  }).catch(err => ({ error: err.message }));

  const callMs = Date.now() - callStart;
  const totalMs = Date.now() - reqStart;

  res.json({
    requestId: uuidv4(),
    service:   'backend-a',
    downstream: result,
    timing: {
      totalMs,
      downstreamCallMs: callMs,
      localProcessingMs: totalMs - callMs
    }
  });
});

const server = http.createServer(app);
server.listen(PORT, () => console.log(`[backend-a] listening on :${PORT}`));
