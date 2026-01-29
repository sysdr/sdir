const express = require('express');
const app = express();
const WebSocket = require('ws');

app.use(express.json());

// CORS: allow dashboard at localhost:8080 to post route requests
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', 'http://localhost:8080');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

// Simulated AI model for routing decisions
class AIRouter {
  constructor() {
    this.edgeNodes = new Map();
    this.requestHistory = [];
    this.carbonIntensity = new Map([
      ['us-west', 0.2],    // High renewable
      ['eu-north', 0.15],  // Very high renewable
      ['asia-east', 0.6],  // Mostly coal
      ['us-east', 0.4]     // Mixed
    ]);
  }

  registerEdge(nodeId, region, capabilities) {
    this.edgeNodes.set(nodeId, {
      region,
      capabilities,
      load: 0,
      latency: Math.random() * 50 + 10,
      lastUpdate: Date.now()
    });
    console.log(`✓ Registered edge node: ${nodeId} in ${region}`);
  }

  // AI-powered routing decision
  routeRequest(request) {
    const { type, priority, userRegion } = request;
    let scores = [];

    for (let [nodeId, node] of this.edgeNodes) {
      let score = 100;

      // Factor 1: Geographic proximity
      const geoScore = userRegion === node.region ? 50 : 0;
      
      // Factor 2: Carbon intensity (sustainability-aware)
      const carbonScore = (1 - this.carbonIntensity.get(node.region)) * 30;
      
      // Factor 3: Current load
      const loadScore = Math.max(0, 20 - node.load);
      
      // Factor 4: Capability match
      const capScore = node.capabilities.includes(type) ? 20 : 0;

      score = geoScore + carbonScore + loadScore + capScore;

      scores.push({
        nodeId,
        score,
        node,
        breakdown: { geoScore, carbonScore, loadScore, capScore }
      });
    }

    scores.sort((a, b) => b.score - a.score);
    const selected = scores[0];

    // Update load
    if (selected) {
      this.edgeNodes.get(selected.nodeId).load++;
      setTimeout(() => {
        const node = this.edgeNodes.get(selected.nodeId);
        if (node) node.load = Math.max(0, node.load - 1);
      }, 2000);
    }

    return selected;
  }

  getStats() {
    const nodes = Array.from(this.edgeNodes.entries()).map(([id, node]) => ({
      id,
      ...node,
      carbonIntensity: this.carbonIntensity.get(node.region)
    }));

    return {
      totalNodes: this.edgeNodes.size,
      nodes,
      totalRequests: this.requestHistory.length,
      recentRequests: this.requestHistory.slice(-10)
    };
  }
}

const router = new AIRouter();

// Initialize edge nodes
router.registerEdge('edge-us-west-1', 'us-west', ['compute', 'wasm', 'gpu']);
router.registerEdge('edge-eu-north-1', 'eu-north', ['compute', 'wasm']);
router.registerEdge('edge-asia-east-1', 'asia-east', ['compute', 'storage']);
router.registerEdge('edge-us-east-1', 'us-east', ['compute', 'wasm', 'storage']);

app.post('/route', (req, res) => {
  const request = req.body;
  const decision = router.routeRequest(request);
  
  const record = {
    timestamp: Date.now(),
    request,
    decision: decision ? {
      nodeId: decision.nodeId,
      region: decision.node.region,
      score: decision.score,
      breakdown: decision.breakdown
    } : null
  };

  router.requestHistory.push(record);
  
  // Broadcast to WebSocket clients
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'routing-decision',
        data: record
      }));
    }
  });

  res.json(record);
});

app.get('/stats', (req, res) => {
  res.json(router.getStats());
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'ai-router' });
});

const server = app.listen(3001, () => {
  console.log('🧠 AI Router running on port 3001');
});

const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
  console.log('WebSocket client connected');
  ws.send(JSON.stringify({
    type: 'stats',
    data: router.getStats()
  }));
});

// Simulate carbon intensity changes
setInterval(() => {
  for (let [region, _] of router.carbonIntensity) {
    const change = (Math.random() - 0.5) * 0.1;
    const current = router.carbonIntensity.get(region);
    router.carbonIntensity.set(region, Math.max(0.1, Math.min(0.9, current + change)));
  }
}, 5000);
