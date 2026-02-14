#!/usr/bin/env node
const http = require('http');
const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3001';

function request(method, path, body=null) {
  return new Promise((resolve, reject) => {
    const url = new URL(BASE_URL + path);
    const opts = { hostname:url.hostname, port:url.port||80, path:url.pathname, method, headers:{'Content-Type':'application/json'} };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', c => data+=c);
      res.on('end', () => { try { resolve({ status:res.statusCode, body:JSON.parse(data) }); } catch { resolve({ status:res.statusCode, body:data }); } });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
let passed=0, failed=0;
function assert(c, name) { if(c) { console.log(`  ✅ PASS: ${name}`); passed++; } else { console.error(`  ❌ FAIL: ${name}`); failed++; } }

async function main() {
  console.log('═══════════════════════════════════════════════════');
  console.log('  Article 202: Connection Storm Test Suite');
  console.log('═══════════════════════════════════════════════════');
  
  let retries = 15;
  while (retries-- > 0) {
    try { const h = await request('GET', '/health'); if(h.status===200) break; } catch {}
    console.log('  Waiting for backend...');
    await sleep(2000);
  }

  console.log('\n🔍 Test: Health');
  const h = await request('GET', '/health');
  assert(h.status === 200, 'Backend healthy');

  console.log('\n🔍 Test: Metrics endpoint');
  const m = await request('GET', '/api/metrics');
  assert(m.status === 200, 'Metrics endpoint responds');
  assert(typeof m.body.connectionStats === 'object', 'Connection stats present');

  console.log('\n🔍 Test: Single direct query');
  const q1 = await request('GET', '/api/query/direct');
  assert(q1.status === 200, 'Direct single query succeeds');

  console.log('\n🔍 Test: Single pooled query');
  const q2 = await request('GET', '/api/query/pooled');
  assert(q2.status === 200, 'Pooled single query succeeds');

  console.log('\n🔍 Test: Metrics reset');
  await request('POST', '/api/reset');
  const m2 = await request('GET', '/api/metrics');
  assert(m2.body.direct.totalRequests === 0, 'Metrics cleared after reset');

  console.log('\n🔍 Test: Storm trigger (direct)');
  const s1 = await request('POST', '/api/storm/direct', { concurrency:25, holdMs:600 });
  assert(s1.status === 200, 'Storm trigger accepted');
  await sleep(4500);
  const m3 = await request('GET', '/api/metrics');
  assert(m3.body.direct.totalRequests >= 20, 'Storm fired requests');
  console.log(`     Rejected: ${m3.body.direct.rejectedRequests}/${m3.body.direct.totalRequests}`);

  console.log('\n🔍 Test: Storm trigger (pooled)');
  await request('POST', '/api/reset');
  const s2 = await request('POST', '/api/storm/pooled', { concurrency:25, holdMs:600 });
  assert(s2.status === 200, 'Pooled storm trigger accepted');
  await sleep(4500);
  const m4 = await request('GET', '/api/metrics');
  assert(m4.body.pooled.totalRequests >= 20, 'Pooled storm fired requests');
  assert(m4.body.pooled.rejectedRequests === 0, 'PgBouncer: zero rejections');
  console.log(`     Pooled rejected: ${m4.body.pooled.rejectedRequests}/${m4.body.pooled.totalRequests}`);

  console.log('\n═══════════════════════════════════════════════════');
  console.log(`  Results: ${passed} passed, ${failed} failed`);
  console.log('═══════════════════════════════════════════════════\n');
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => { console.error(err); process.exit(1); });
