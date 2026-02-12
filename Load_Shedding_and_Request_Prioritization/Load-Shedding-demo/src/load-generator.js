import http from 'http';

const TARGET_HOST = process.env.TARGET_HOST || 'localhost';
const TARGET_PORT = parseInt(process.env.TARGET_PORT || '3000', 10);

const endpoints = [
  { path: '/api/checkout', weight: 5 },
  { path: '/api/payment', weight: 5 },
  { path: '/api/order', weight: 10 },
  { path: '/api/user', weight: 15 },
  { path: '/api/search', weight: 20 },
  { path: '/api/browse', weight: 20 },
  { path: '/api/analytics', weight: 15 },
  { path: '/api/recommendations', weight: 10 }
];

const userTiers = ['free', 'premium'];

function selectEndpoint() {
  const totalWeight = endpoints.reduce((sum, e) => sum + e.weight, 0);
  let random = Math.random() * totalWeight;
  
  for (const endpoint of endpoints) {
    random -= endpoint.weight;
    if (random <= 0) return endpoint.path;
  }
  
  return endpoints[0].path;
}

function makeRequest() {
  const path = selectEndpoint();
  const userTier = Math.random() < 0.3 ? 'premium' : 'free';
  
  const options = {
    hostname: TARGET_HOST,
    port: TARGET_PORT,
    path,
    method: 'GET',
    headers: {
      'X-User-Tier': userTier
    }
  };
  
  const req = http.request(options, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      // Silent - just generate load
    });
  });
  
  req.on('error', () => {
    // Silent - expected during load shedding
  });
  
  req.end();
}

// Start with moderate load, then increase
let requestsPerSecond = 500;
console.log(`Starting load generator: ${requestsPerSecond} req/s`);

setInterval(() => {
  const requestsPerInterval = requestsPerSecond / 10; // 100ms interval
  for (let i = 0; i < requestsPerInterval; i++) {
    makeRequest();
  }
}, 100);

// Gradually increase load
setInterval(() => {
  if (requestsPerSecond < 5000) {
    requestsPerSecond += 200;
    console.log(`Increasing load: ${requestsPerSecond} req/s`);
  }
}, 10000);
