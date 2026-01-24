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
