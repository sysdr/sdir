#!/usr/bin/env node
/**
 * Edge Caching Demo - Integration Tests
 * Run with: node tests/test.js
 * Requires: Services running (docker-compose up -d)
 */

const http = require('http');
const WebSocket = require('ws');

const DASHBOARD_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';
const TIMEOUT_MS = 45000;

let passed = 0;
let failed = 0;

function test(name, fn) {
  return fn()
    .then(() => {
      console.log(`✅ ${name}`);
      passed++;
    })
    .catch((err) => {
      console.log(`❌ ${name}: ${err.message}`);
      failed++;
    });
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('🧪 Running Edge Caching Demo Tests...\n');

  await test('Dashboard HTTP is accessible', async () => {
    return new Promise((resolve, reject) => {
      const req = http.get(DASHBOARD_URL, (res) => {
        if (res.statusCode === 200) resolve();
        else reject(new Error(`Status ${res.statusCode}`));
      });
      req.on('error', reject);
      req.setTimeout(5000, () => {
        req.destroy();
        reject(new Error('Timeout'));
      });
    });
  });

  await test('Dashboard serves HTML content', async () => {
    return new Promise((resolve, reject) => {
      http.get(DASHBOARD_URL, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          if (data.includes('Edge Caching') && data.includes('metrics')) resolve();
          else reject(new Error('Invalid HTML content'));
        });
      }).on('error', reject);
    });
  });

  await test('WebSocket connects and receives metrics', async () => {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('Timeout waiting for metrics'));
      }, TIMEOUT_MS);

      const ws = new WebSocket(WS_URL);
      ws.on('error', (err) => {
        clearTimeout(timeout);
        reject(err);
      });

      ws.on('open', () => {
        // Load generator runs every 200ms, metrics broadcast every 2s
        // Wait for at least one metrics update
      });

      ws.on('message', (data) => {
        try {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'metrics' && msg.data) {
            let hasNonZero = false;
            for (const [region, metrics] of Object.entries(msg.data)) {
              if (region !== 'origin' && metrics && !metrics.error) {
                const total = metrics.totalRequests || 0;
                const hits = metrics.cacheHits || 0;
                const misses = metrics.cacheMisses || 0;
                if (total > 0 || hits > 0 || misses > 0) {
                  hasNonZero = true;
                  break;
                }
              }
              if (region === 'origin' && metrics && !metrics.error) {
                if ((metrics.requests || 0) > 0) hasNonZero = true;
              }
            }
            if (hasNonZero) {
              clearTimeout(timeout);
              ws.close();
              resolve();
            }
          }
        } catch (_) {}
      });
    });
  });

  await wait(1000);

  console.log(`\n📊 Test Results: ${passed} passed, ${failed} failed`);

  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error('Test runner error:', err);
  process.exit(1);
});
