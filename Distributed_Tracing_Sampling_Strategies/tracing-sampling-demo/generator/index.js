const axios = require('axios');
const { v4: uuidv4 } = require('uuid');

const COLLECTOR_URL = process.env.COLLECTOR_URL || 'http://collector:3000';
const TRACE_RATE    = parseInt(process.env.TRACE_RATE || '15'); // traces/sec

// Simulated microservice topology
const SERVICES = [
  { name: 'api-gateway',     color: '#1a73e8' },
  { name: 'auth-service',    color: '#0d47a1' },
  { name: 'order-service',   color: '#1565c0' },
  { name: 'payment-service', color: '#0277bd' },
];

const OPERATIONS = {
  'api-gateway':     ['GET /api/orders', 'POST /api/checkout', 'GET /api/user/profile', 'DELETE /api/cart'],
  'auth-service':    ['validateToken', 'refreshSession', 'checkPermissions'],
  'order-service':   ['createOrder', 'fetchOrderHistory', 'updateOrderStatus'],
  'payment-service': ['chargeCard', 'refundTransaction', 'validatePaymentMethod'],
};

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Build a realistic multi-hop trace tree
function generateTrace(type) {
  const traceId   = uuidv4().replace(/-/g, '');
  const startTime = Date.now();
  const spans     = [];

  // Determine profile based on type
  const profile = {
    normal: { latencyBase: 50,  latencyJitter: 40,  errorProb: 0.00, dbSlowProb: 0.05 },
    slow:   { latencyBase: 400, latencyJitter: 300, errorProb: 0.03, dbSlowProb: 0.60 },
    error:  { latencyBase: 80,  latencyJitter: 40,  errorProb: 0.90, dbSlowProb: 0.10 },
  }[type];

  // Root span (API Gateway)
  const rootSpanId = uuidv4().replace(/-/g, '').slice(0, 16);
  const rootOp = OPERATIONS['api-gateway'][randomInt(0, OPERATIONS['api-gateway'].length - 1)];

  let cursor = startTime;

  // Decide service chain (1–4 hops)
  const hopCount   = type === 'error' ? randomInt(2, 4) : randomInt(2, 4);
  const serviceChain = SERVICES.slice(0, hopCount);
  let parentSpanId = rootSpanId;
  let totalDuration = 0;

  serviceChain.forEach((svc, idx) => {
    const spanId   = idx === 0 ? rootSpanId : uuidv4().replace(/-/g, '').slice(0, 16);
    const ops      = OPERATIONS[svc.name];
    const op       = idx === 0 ? rootOp : ops[randomInt(0, ops.length - 1)];
    const isError  = Math.random() < profile.errorProb && idx === hopCount - 1;
    const isSlowDb = svc.name === 'order-service' && Math.random() < profile.dbSlowProb;

    const spanLatency = isSlowDb
      ? randomInt(800, 2000)
      : randomInt(profile.latencyBase, profile.latencyBase + profile.latencyJitter);

    spans.push({
      traceId,
      spanId,
      parentSpanId: idx === 0 ? null : parentSpanId,
      service:      svc.name,
      operation:    op,
      startTime:    cursor,
      duration:     spanLatency,
      status:       isError ? 'ERROR' : 'OK',
      statusCode:   isError ? (Math.random() < 0.5 ? 500 : 503) : 200,
      tags: {
        'span.kind':   idx === 0 ? 'server' : 'client',
        'db.slow':     isSlowDb ? 'true' : 'false',
        'http.status': isError ? String(Math.random() < 0.5 ? 500 : 503) : '200',
        ...(isSlowDb ? { 'db.statement': 'SELECT * FROM orders WHERE user_id = ?', 'db.duration_ms': String(spanLatency) } : {}),
      },
    });

    cursor += spanLatency;
    totalDuration += spanLatency;
    parentSpanId = spanId;
  });

  const endTime = cursor;
  spans[0].totalDuration = totalDuration;

  return {
    traceId,
    type,
    totalDuration,
    startTime,
    endTime,
    spanCount: spans.length,
    hasError:  spans.some(s => s.status === 'ERROR'),
    spans,
  };
}

async function sendTrace(trace) {
  try {
    await axios.post(`${COLLECTOR_URL}/trace`, trace, { timeout: 5000 });
  } catch (e) {
    // Collector may be starting up
  }
}

async function run() {
  console.log(`[Generator] Starting — target ${TRACE_RATE} traces/sec → ${COLLECTOR_URL}`);
  await new Promise(r => setTimeout(r, 3000)); // wait for collector

  const intervalMs = 1000 / TRACE_RATE;
  let seq = 0;

  setInterval(async () => {
    const rand = Math.random();
    const type = rand < 0.60 ? 'normal' : rand < 0.85 ? 'slow' : 'error';
    const trace = generateTrace(type);
    await sendTrace(trace);
    seq++;
    if (seq % 50 === 0) {
      console.log(`[Generator] Sent ${seq} traces (last: ${type}, ${trace.spanCount} spans, ${trace.totalDuration}ms)`);
    }
  }, intervalMs);
}

run();
