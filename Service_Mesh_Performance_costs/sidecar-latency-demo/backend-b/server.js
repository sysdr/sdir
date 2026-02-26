const express = require('express');
const http    = require('http');
const { v4: uuidv4 } = require('uuid');

const app  = express();
const PORT = process.env.PORT || 3002;

function simulateWork(min = 1, max = 8) {
  return new Promise(resolve => setTimeout(resolve, min + Math.random() * (max - min)));
}

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'backend-b' }));

app.get('/api/data', async (req, res) => {
  const start = Date.now();
  await simulateWork(1, 8);
  const appMs = Date.now() - start;
  res.json({
    requestId: uuidv4(),
    service:   'backend-b',
    appProcessingMs: appMs,
    timestamp: Date.now(),
    data: { value: Math.random() * 1000 }
  });
});

const server = http.createServer(app);
server.listen(PORT, () => console.log(`[backend-b] listening on :${PORT}`));
