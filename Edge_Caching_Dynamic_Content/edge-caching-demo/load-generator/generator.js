const axios = require('axios');
const WebSocket = require('ws');
const config = require('../shared/config');

const ws = new WebSocket('ws://dashboard:3000');

const ENDPOINTS = [
  { path: '/api/catalog', weight: 50, cacheable: true },
  { path: '/api/recommendations', weight: 30, cacheable: true },
  { path: '/api/user-balance', weight: 20, cacheable: false }
];

const generateRequest = () => {
  const rand = Math.random() * 100;
  let cumulative = 0;
  
  for (const endpoint of ENDPOINTS) {
    cumulative += endpoint.weight;
    if (rand < cumulative) {
      return endpoint;
    }
  }
  
  return ENDPOINTS[0];
};

const makeRequest = async () => {
  const region = config.REGIONS[Math.floor(Math.random() * config.REGIONS.length)];
  const tier = config.USER_TIERS[Math.floor(Math.random() * config.USER_TIERS.length)];
  const endpoint = generateRequest();
  
  const edgePort = config.EDGE_PORTS[region];
  const url = `http://edge-${region}:${edgePort}${endpoint.path}`;
  
  const startTime = Date.now();
  
  try {
    const response = await axios.get(url, {
      params: { region, tier, userId: `user-${Math.floor(Math.random() * 100)}` },
      timeout: 5000
    });
    
    const latency = Date.now() - startTime;
    
    const event = {
      type: 'request',
      timestamp: Date.now(),
      region,
      tier,
      endpoint: endpoint.path,
      latency,
      cacheStatus: response.headers['x-cache-status'],
      edgeLatency: parseInt(response.headers['x-edge-latency'] || '0'),
      originLatency: parseInt(response.headers['x-origin-latency'] || '0')
    };
    
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(event));
    }
    
  } catch (error) {
    console.error('Request failed:', error.message);
  }
};

// Traffic patterns
const runTraffic = () => {
  // Steady traffic
  setInterval(makeRequest, 200);
  
  // Burst traffic every 30 seconds
  setInterval(() => {
    for (let i = 0; i < 20; i++) {
      setTimeout(makeRequest, i * 50);
    }
  }, 30000);
};

setTimeout(() => {
  console.log('🔥 Load generator starting...');
  runTraffic();
}, 3000);
