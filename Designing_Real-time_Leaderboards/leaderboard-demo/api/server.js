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
        score: Math.floor(parseFloat(results[i + 1]))
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
      score: Math.floor(parseFloat(score)),
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
        score: Math.floor(parseFloat(topScore[1]))
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
          score: Math.floor(parseFloat(top10[i + 1]))
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
