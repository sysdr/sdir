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
