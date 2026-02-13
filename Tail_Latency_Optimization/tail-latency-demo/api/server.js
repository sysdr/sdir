const express = require('express');
const cors = require('cors');
const hdr = require('hdr-histogram-js');

const app = express();
app.use(cors());
app.use(express.json());

// HDR Histogram for accurate percentile tracking (1μs to 1 minute range)
const histogram = hdr.build({
  lowestDiscernibleValue: 1,
  highestTrackableValue: 60000,
  numberOfSignificantValueDigits: 3
});

const requestHistory = [];
const MAX_HISTORY = 1000;

// Latency injection configurations
const SCENARIOS = {
  fast: { baseLatency: 10, variance: 5, gcProbability: 0 },
  normal: { baseLatency: 50, variance: 20, gcProbability: 0.01 },
  withGC: { baseLatency: 50, variance: 20, gcProbability: 0.10 },
  slowQuery: { baseLatency: 80, variance: 30, gcProbability: 0.01, slowQueryProb: 0.05 },
  contention: { baseLatency: 60, variance: 25, gcProbability: 0.02, lockContentionProb: 0.08 }
};

let currentScenario = 'normal';
let queueDepth = 0;
let circuitBreakerOpen = false;
let hedgingEnabled = false;

// Simulate various latency sources
async function simulateLatency(scenario) {
  const config = SCENARIOS[scenario];
  const startTime = Date.now();
  
  // Base latency with variance
  let latency = config.baseLatency + (Math.random() - 0.5) * config.variance * 2;
  
  // Simulate GC pause (long tail event)
  if (Math.random() < config.gcProbability) {
    latency += 200 + Math.random() * 300; // 200-500ms GC pause
  }
  
  // Simulate slow database query (tail latency)
  if (config.slowQueryProb && Math.random() < config.slowQueryProb) {
    latency += 500 + Math.random() * 1000; // 500-1500ms slow query
  }
  
  // Simulate lock contention
  if (config.lockContentionProb && Math.random() < config.lockContentionProb) {
    latency += 100 + Math.random() * 200; // 100-300ms lock wait
  }
  
  // Add network jitter
  if (Math.random() < 0.1) {
    latency += Math.random() * 50; // 0-50ms network spike
  }
  
  await new Promise(resolve => setTimeout(resolve, latency));
  
  const actualLatency = Date.now() - startTime;
  return actualLatency;
}

// Main request handler
app.get('/api/request', async (req, res) => {
  queueDepth++;
  const requestId = Date.now() + Math.random();
  const startTime = Date.now();
  
  try {
    // Circuit breaker check
    if (circuitBreakerOpen && Math.random() < 0.9) {
      queueDepth--;
      return res.status(503).json({ 
        error: 'Circuit breaker open',
        queueDepth,
        circuitBreaker: 'open'
      });
    }
    
    // Shed load if queue too deep
    if (queueDepth > 50) {
      queueDepth--;
      return res.status(503).json({ 
        error: 'Queue depth exceeded',
        queueDepth,
        shed: true
      });
    }
    
    const latency = await simulateLatency(currentScenario);
    
    // Record in histogram
    histogram.recordValue(latency);
    
    // Keep request history
    const requestData = {
      id: requestId,
      timestamp: Date.now(),
      latency,
      scenario: currentScenario,
      queueDepth: queueDepth - 1
    };
    
    requestHistory.push(requestData);
    if (requestHistory.length > MAX_HISTORY) {
      requestHistory.shift();
    }
    
    queueDepth--;
    
    res.json({
      requestId,
      latency,
      scenario: currentScenario,
      queueDepth: queueDepth,
      success: true
    });
    
  } catch (error) {
    queueDepth--;
    res.status(500).json({ error: error.message });
  }
});

// Get metrics endpoint
app.get('/api/metrics', (req, res) => {
  const stats = {
    totalRequests: histogram.totalCount,
    p50: histogram.getValueAtPercentile(50),
    p95: histogram.getValueAtPercentile(95),
    p99: histogram.getValueAtPercentile(99),
    p999: histogram.getValueAtPercentile(99.9),
    p9999: histogram.getValueAtPercentile(99.99),
    min: histogram.minNonZeroValue,
    max: histogram.maxValue,
    mean: histogram.mean,
    stdDev: histogram.stdDeviation,
    queueDepth,
    currentScenario,
    circuitBreakerOpen,
    hedgingEnabled,
    recentRequests: requestHistory.slice(-50)
  };
  
  res.json(stats);
});

// Control endpoints
app.post('/api/scenario', (req, res) => {
  const { scenario } = req.body;
  if (SCENARIOS[scenario]) {
    currentScenario = scenario;
    res.json({ currentScenario, config: SCENARIOS[scenario] });
  } else {
    res.status(400).json({ error: 'Invalid scenario', available: Object.keys(SCENARIOS) });
  }
});

app.post('/api/circuit-breaker', (req, res) => {
  const { open } = req.body;
  circuitBreakerOpen = open;
  res.json({ circuitBreakerOpen });
});

app.post('/api/reset', (req, res) => {
  histogram.reset();
  requestHistory.length = 0;
  queueDepth = 0;
  res.json({ message: 'Metrics reset' });
});

app.listen(3001, () => {
  console.log('📊 Tail Latency API running on port 3001');
  console.log('Available scenarios:', Object.keys(SCENARIOS));
});
