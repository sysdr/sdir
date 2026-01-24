#!/bin/bash

set -e

echo "========================================="
echo "Real-Time Leaderboard Demo Setup"
echo "Redis Sorted Sets in Action"
echo "========================================="

# 1. Create directory structure
echo ""
echo "Creating directory structure..."
mkdir -p leaderboard-demo/{api,frontend,simulator,tests}

# 2. Generate backend API service
echo "Generating backend API..."
cat > leaderboard-demo/api/server.js << 'EOF'
const express = require('express');
const Redis = require('ioredis');
const cors = require('cors');

const app = express();
const redis = new Redis({
  host: process.env.REDIS_HOST || 'redis',
  port: 6379,
  retryStrategy: (times) => Math.min(times * 50, 2000)
});

app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: Date.now() });
});

// Get top N players from leaderboard
app.get('/leaderboard/top/:limit', async (req, res) => {
  try {
    const limit = parseInt(req.params.limit) || 100;
    // ZREVRANGE returns members in descending score order
    const results = await redis.zrevrange('leaderboard:global', 0, limit - 1, 'WITHSCORES');
    
    const leaderboard = [];
    for (let i = 0; i < results.length; i += 2) {
      leaderboard.push({
        rank: (i / 2) + 1,
        player: results[i],
        score: parseInt(results[i + 1])
      });
    }
    
    res.json({ leaderboard, total: await redis.zcard('leaderboard:global') });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get player rank and score
app.get('/player/:playerId', async (req, res) => {
  try {
    const { playerId } = req.params;
    const score = await redis.zscore('leaderboard:global', playerId);
    const rank = await redis.zrevrank('leaderboard:global', playerId);
    
    if (score === null) {
      return res.status(404).json({ error: 'Player not found' });
    }
    
    res.json({
      player: playerId,
      score: parseInt(score),
      rank: rank + 1  // Redis ranks are 0-indexed
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update player score (absolute)
app.post('/score/set', async (req, res) => {
  try {
    const { playerId, score } = req.body;
    
    // Add timestamp to score to handle ties consistently
    const scoreWithTimestamp = score + (Date.now() / 1e13);
    
    await redis.zadd('leaderboard:global', scoreWithTimestamp, playerId);
    const rank = await redis.zrevrank('leaderboard:global', playerId);
    
    res.json({
      player: playerId,
      score,
      rank: rank + 1,
      timestamp: Date.now()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Increment player score (cumulative)
app.post('/score/increment', async (req, res) => {
  try {
    const { playerId, increment } = req.body;
    
    // ZINCRBY is atomic and more efficient than get-then-set
    await redis.zincrby('leaderboard:global', increment, playerId);
    const score = await redis.zscore('leaderboard:global', playerId);
    const rank = await redis.zrevrank('leaderboard:global', playerId);
    
    res.json({
      player: playerId,
      score: Math.floor(parseFloat(score)),
      rank: rank + 1,
      timestamp: Date.now()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get statistics
app.get('/stats', async (req, res) => {
  try {
    const totalPlayers = await redis.zcard('leaderboard:global');
    const topScore = await redis.zrevrange('leaderboard:global', 0, 0, 'WITHSCORES');
    const memoryInfo = await redis.info('memory');
    
    res.json({
      totalPlayers,
      topScore: topScore.length > 0 ? {
        player: topScore[0],
        score: parseInt(topScore[1])
      } : null,
      memoryUsed: memoryInfo.match(/used_memory_human:(.+)/)?.[1] || 'N/A',
      timestamp: Date.now()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Stream real-time updates
app.get('/stream', async (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  
  const interval = setInterval(async () => {
    try {
      const top10 = await redis.zrevrange('leaderboard:global', 0, 9, 'WITHSCORES');
      const leaderboard = [];
      
      for (let i = 0; i < top10.length; i += 2) {
        leaderboard.push({
          rank: (i / 2) + 1,
          player: top10[i],
          score: parseInt(top10[i + 1])
        });
      }
      
      res.write(`data: ${JSON.stringify(leaderboard)}\n\n`);
    } catch (error) {
      console.error('Stream error:', error);
    }
  }, 1000);
  
  req.on('close', () => clearInterval(interval));
});

const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Leaderboard API running on port ${PORT}`);
});
EOF

cat > leaderboard-demo/api/package.json << 'EOF'
{
  "name": "leaderboard-api",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "cors": "^2.8.5"
  }
}
EOF

# 3. Generate frontend dashboard
echo "Generating frontend dashboard..."
cat > leaderboard-demo/frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Real-Time Leaderboard Dashboard</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      padding: 20px;
    }

    .container {
      max-width: 1400px;
      margin: 0 auto;
    }

    .header {
      background: white;
      border-radius: 16px;
      padding: 30px;
      margin-bottom: 20px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
    }

    h1 {
      color: #2d3748;
      font-size: 32px;
      margin-bottom: 10px;
    }

    .subtitle {
      color: #718096;
      font-size: 16px;
    }

    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }

    .stat-card {
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
    }

    .stat-label {
      color: #718096;
      font-size: 14px;
      font-weight: 500;
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .stat-value {
      color: #2d3748;
      font-size: 36px;
      font-weight: 700;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .leaderboard-container {
      background: white;
      border-radius: 16px;
      padding: 30px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
    }

    .leaderboard-title {
      color: #2d3748;
      font-size: 24px;
      margin-bottom: 20px;
      padding-bottom: 15px;
      border-bottom: 3px solid #667eea;
    }

    .leaderboard-table {
      width: 100%;
      border-collapse: separate;
      border-spacing: 0 8px;
    }

    .leaderboard-table thead th {
      color: #718096;
      font-size: 13px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      padding: 12px;
      text-align: left;
      border-bottom: 2px solid #e2e8f0;
    }

    .leaderboard-table tbody tr {
      background: #f7fafc;
      transition: all 0.3s ease;
    }

    .leaderboard-table tbody tr:hover {
      background: #edf2f7;
      transform: translateX(4px);
    }

    .leaderboard-table tbody td {
      padding: 16px 12px;
      color: #2d3748;
      font-size: 15px;
    }

    .rank-cell {
      font-weight: 700;
      font-size: 18px;
      width: 60px;
    }

    .rank-1 { color: #f59e0b; }
    .rank-2 { color: #94a3b8; }
    .rank-3 { color: #d97706; }

    .player-cell {
      font-weight: 600;
      color: #4c51bf;
    }

    .score-cell {
      font-weight: 700;
      color: #10b981;
      text-align: right;
    }

    .pulse {
      animation: pulse 2s ease-in-out infinite;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.6; }
    }

    .live-indicator {
      display: inline-block;
      width: 10px;
      height: 10px;
      background: #10b981;
      border-radius: 50%;
      margin-right: 8px;
      animation: blink 1.5s ease-in-out infinite;
    }

    @keyframes blink {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }

    .update-time {
      color: #94a3b8;
      font-size: 13px;
      margin-top: 15px;
      text-align: center;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1><span class="live-indicator"></span>Real-Time Leaderboard</h1>
      <p class="subtitle">Powered by Redis Sorted Sets • Live Updates Every Second</p>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-label">Total Players</div>
        <div class="stat-value" id="totalPlayers">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Top Score</div>
        <div class="stat-value" id="topScore">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Memory Used</div>
        <div class="stat-value" id="memoryUsed" style="font-size: 28px;">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Updates/sec</div>
        <div class="stat-value" id="updatesPerSec">0</div>
      </div>
    </div>

    <div class="leaderboard-container">
      <h2 class="leaderboard-title">🏆 Global Top 20</h2>
      <table class="leaderboard-table">
        <thead>
          <tr>
            <th>Rank</th>
            <th>Player</th>
            <th style="text-align: right;">Score</th>
          </tr>
        </thead>
        <tbody id="leaderboardBody">
          <tr><td colspan="3" style="text-align: center; padding: 40px;">Loading...</td></tr>
        </tbody>
      </table>
      <div class="update-time" id="updateTime">Connecting...</div>
    </div>
  </div>

  <script>
    const API_URL = 'http://localhost:3000';
    let updateCount = 0;
    let lastUpdate = Date.now();

    // Fetch statistics
    async function fetchStats() {
      try {
        const response = await fetch(`${API_URL}/stats`);
        const data = await response.json();
        
        document.getElementById('totalPlayers').textContent = data.totalPlayers.toLocaleString();
        document.getElementById('topScore').textContent = data.topScore?.score?.toLocaleString() || '0';
        document.getElementById('memoryUsed').textContent = data.memoryUsed;
      } catch (error) {
        console.error('Stats fetch error:', error);
      }
    }

    // Stream leaderboard updates
    function streamLeaderboard() {
      const eventSource = new EventSource(`${API_URL}/stream`);
      
      eventSource.onmessage = (event) => {
        const leaderboard = JSON.parse(event.data);
        updateLeaderboard(leaderboard);
        
        // Calculate updates per second
        updateCount++;
        const now = Date.now();
        if (now - lastUpdate >= 1000) {
          document.getElementById('updatesPerSec').textContent = updateCount;
          updateCount = 0;
          lastUpdate = now;
        }
      };

      eventSource.onerror = () => {
        console.error('Stream connection error');
        setTimeout(streamLeaderboard, 5000);
      };
    }

    function updateLeaderboard(data) {
      const tbody = document.getElementById('leaderboardBody');
      tbody.innerHTML = data.map((entry, index) => {
        const rankClass = index === 0 ? 'rank-1' : index === 1 ? 'rank-2' : index === 2 ? 'rank-3' : '';
        const medal = index === 0 ? '🥇 ' : index === 1 ? '🥈 ' : index === 2 ? '🥉 ' : '';
        
        return `
          <tr>
            <td class="rank-cell ${rankClass}">${medal}#${entry.rank}</td>
            <td class="player-cell">${entry.player}</td>
            <td class="score-cell">${entry.score.toLocaleString()}</td>
          </tr>
        `;
      }).join('');
      
      document.getElementById('updateTime').textContent = 
        `Last update: ${new Date().toLocaleTimeString()}`;
    }

    // Initialize
    fetchStats();
    setInterval(fetchStats, 5000);
    streamLeaderboard();
  </script>
</body>
</html>
EOF

cat > leaderboard-demo/frontend/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
EOF

# 4. Generate score simulator
echo "Generating score simulator..."
cat > leaderboard-demo/simulator/simulator.js << 'EOF'
const axios = require('axios');

const API_URL = process.env.API_URL || 'http://api:3000';
const NUM_PLAYERS = 1000;
const UPDATE_INTERVAL = 100; // ms

// Generate player names
const players = Array.from({ length: NUM_PLAYERS }, (_, i) => `player${String(i + 1).padStart(4, '0')}`);

// Initialize players with random scores
async function initializePlayers() {
  console.log('Initializing players...');
  
  for (let i = 0; i < players.length; i += 50) {
    const batch = players.slice(i, i + 50);
    await Promise.all(batch.map(async (player) => {
      const score = Math.floor(Math.random() * 100000);
      try {
        await axios.post(`${API_URL}/score/set`, { playerId: player, score });
      } catch (error) {
        // Retry on error
        console.error(`Error initializing ${player}:`, error.message);
      }
    }));
    
    if (i % 200 === 0) {
      console.log(`Initialized ${i} players...`);
    }
  }
  
  console.log('All players initialized!');
}

// Simulate continuous score updates
async function simulateScoreUpdates() {
  console.log('Starting score simulation...');
  
  setInterval(async () => {
    // Pick 10 random players to update
    const playersToUpdate = [];
    for (let i = 0; i < 10; i++) {
      playersToUpdate.push(players[Math.floor(Math.random() * players.length)]);
    }
    
    await Promise.all(playersToUpdate.map(async (player) => {
      try {
        // 80% chance of increment, 20% chance of new absolute score
        if (Math.random() < 0.8) {
          const increment = Math.floor(Math.random() * 1000) + 100;
          await axios.post(`${API_URL}/score/increment`, { playerId: player, increment });
        } else {
          const score = Math.floor(Math.random() * 150000);
          await axios.post(`${API_URL}/score/set`, { playerId: player, score });
        }
      } catch (error) {
        // Silent failure for demo
      }
    }));
  }, UPDATE_INTERVAL);
}

// Wait for API to be ready
async function waitForAPI() {
  console.log('Waiting for API to be ready...');
  
  let attempts = 0;
  while (attempts < 30) {
    try {
      await axios.get(`${API_URL}/health`);
      console.log('API is ready!');
      return true;
    } catch (error) {
      attempts++;
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
  
  throw new Error('API failed to start');
}

// Main
async function main() {
  await waitForAPI();
  await initializePlayers();
  await simulateScoreUpdates();
}

main().catch(console.error);
EOF

cat > leaderboard-demo/simulator/package.json << 'EOF'
{
  "name": "leaderboard-simulator",
  "version": "1.0.0",
  "main": "simulator.js",
  "dependencies": {
    "axios": "^1.6.2"
  }
}
EOF

cat > leaderboard-demo/simulator/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY simulator.js ./
CMD ["node", "simulator.js"]
EOF

# 5. Generate tests
echo "Generating test suite..."
cat > leaderboard-demo/tests/test.js << 'EOF'
const axios = require('axios');
const assert = require('assert');

const API_URL = process.env.API_URL || 'http://localhost:3000';

async function runTests() {
  console.log('\n========================================');
  console.log('Running Leaderboard Tests');
  console.log('========================================\n');

  let passed = 0;
  let failed = 0;

  // Test 1: Health check
  try {
    const response = await axios.get(`${API_URL}/health`);
    assert.strictEqual(response.data.status, 'healthy');
    console.log('✓ Test 1: Health check passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 1: Health check failed');
    failed++;
  }

  // Test 2: Set player score
  try {
    const response = await axios.post(`${API_URL}/score/set`, {
      playerId: 'test_player1',
      score: 5000
    });
    assert.strictEqual(response.data.player, 'test_player1');
    assert.strictEqual(response.data.score, 5000);
    console.log('✓ Test 2: Set player score passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 2: Set player score failed:', error.message);
    failed++;
  }

  // Test 3: Increment player score
  try {
    await axios.post(`${API_URL}/score/set`, {
      playerId: 'test_player2',
      score: 1000
    });
    
    const response = await axios.post(`${API_URL}/score/increment`, {
      playerId: 'test_player2',
      increment: 500
    });
    
    assert.strictEqual(response.data.player, 'test_player2');
    assert(response.data.score >= 1500); // Account for timestamp decimals
    console.log('✓ Test 3: Increment player score passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 3: Increment player score failed:', error.message);
    failed++;
  }

  // Test 4: Get player rank
  try {
    const response = await axios.get(`${API_URL}/player/test_player1`);
    assert.strictEqual(response.data.player, 'test_player1');
    assert(response.data.rank > 0);
    console.log('✓ Test 4: Get player rank passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 4: Get player rank failed:', error.message);
    failed++;
  }

  // Test 5: Get top leaderboard
  try {
    const response = await axios.get(`${API_URL}/leaderboard/top/10`);
    assert(Array.isArray(response.data.leaderboard));
    assert(response.data.leaderboard.length > 0);
    console.log('✓ Test 5: Get top leaderboard passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 5: Get top leaderboard failed:', error.message);
    failed++;
  }

  // Test 6: Get statistics
  try {
    const response = await axios.get(`${API_URL}/stats`);
    assert(response.data.totalPlayers > 0);
    assert(response.data.topScore !== null);
    console.log('✓ Test 6: Get statistics passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 6: Get statistics failed:', error.message);
    failed++;
  }

  // Test 7: Verify ranking order
  try {
    await axios.post(`${API_URL}/score/set`, { playerId: 'test_high', score: 99999 });
    await axios.post(`${API_URL}/score/set`, { playerId: 'test_low', score: 100 });
    
    const response = await axios.get(`${API_URL}/leaderboard/top/100`);
    const highRank = response.data.leaderboard.find(p => p.player === 'test_high')?.rank;
    const lowRank = response.data.leaderboard.find(p => p.player === 'test_low')?.rank;
    
    assert(highRank < lowRank, 'High score should rank higher');
    console.log('✓ Test 7: Verify ranking order passed');
    passed++;
  } catch (error) {
    console.log('✗ Test 7: Verify ranking order failed:', error.message);
    failed++;
  }

  console.log('\n========================================');
  console.log(`Tests Complete: ${passed} passed, ${failed} failed`);
  console.log('========================================\n');

  process.exit(failed > 0 ? 1 : 0);
}

// Wait for API
setTimeout(runTests, 3000);
EOF

cat > leaderboard-demo/tests/package.json << 'EOF'
{
  "name": "leaderboard-tests",
  "version": "1.0.0",
  "dependencies": {
    "axios": "^1.6.2"
  }
}
EOF

# 6. Generate API Dockerfile
cat > leaderboard-demo/api/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY server.js ./
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# 7. Generate docker-compose
echo "Generating docker-compose..."
cat > leaderboard-demo/docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: leaderboard-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  api:
    build: ./api
    container_name: leaderboard-api
    ports:
      - "3000:3000"
    depends_on:
      redis:
        condition: service_healthy
    environment:
      - REDIS_HOST=redis
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  frontend:
    build: ./frontend
    container_name: leaderboard-frontend
    ports:
      - "8080:80"
    depends_on:
      - api

  simulator:
    build: ./simulator
    container_name: leaderboard-simulator
    depends_on:
      api:
        condition: service_healthy
    environment:
      - API_URL=http://api:3000

volumes:
  redis-data:
EOF

# 8. Build and run
echo ""
echo "Building Docker containers..."
cd leaderboard-demo
docker-compose build --no-cache

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to be healthy..."
sleep 5

# 9. Run tests
echo ""
echo "Running tests..."
# Get the actual network name created by docker-compose
NETWORK_NAME=$(docker network ls --filter name=leaderboard --format "{{.Name}}" | head -1)
if [ -z "$NETWORK_NAME" ]; then
  NETWORK_NAME="leaderboard-demo_default"
fi
docker run --rm --network "$NETWORK_NAME" \
  -e API_URL=http://api:3000 \
  -v $(pwd)/tests:/app \
  -w /app \
  node:20-alpine sh -c "npm install --silent && node test.js"

# 10. Display demo instructions
echo ""
echo "========================================="
echo "✓ Real-Time Leaderboard Demo Running!"
echo "========================================="
echo ""
echo "📊 Open Dashboard:"
echo "   http://localhost:8080"
echo ""
echo "🔌 API Endpoints:"
echo "   http://localhost:3000/leaderboard/top/20"
echo "   http://localhost:3000/player/player0001"
echo "   http://localhost:3000/stats"
echo ""
echo "📈 What You'll See:"
echo "   • 1,000 players competing in real-time"
echo "   • Scores updating every 100ms"
echo "   • Live rankings changing instantly"
echo "   • Redis Sorted Sets maintaining order atomically"
echo ""
echo "🔧 Try These Commands:"
echo "   docker exec -it leaderboard-redis redis-cli"
echo "   > ZREVRANGE leaderboard:global 0 9 WITHSCORES"
echo "   > ZCARD leaderboard:global"
echo "   > ZSCORE leaderboard:global player0001"
echo ""
echo "🧹 Cleanup:"
echo "   cd leaderboard-demo && docker-compose down -v"
echo ""
echo "========================================="