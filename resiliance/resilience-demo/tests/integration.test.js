const axios = require('axios');

const BASE_URL = 'http://localhost:3001';
const CHAOS_URL = 'http://localhost:3004';

describe('Resilience Testing Integration', () => {
  test('should handle normal requests', async () => {
    const response = await axios.get(`${BASE_URL}/api/users/1`);
    expect(response.status).toBe(200);
    expect(response.data.id).toBe('1');
  });

  test('should handle chaos experiments', async () => {
    // Start latency experiment
    const experiment = {
      experimentId: 'test-latency',
      targetService: 'database-service',
      type: 'latency',
      parameters: { latencyMs: 100 },
      duration: 5
    };

    const startResponse = await axios.post(`${CHAOS_URL}/chaos/start`, experiment);
    expect(startResponse.status).toBe(200);

    // Test that requests still work with added latency
    const userResponse = await axios.get(`${BASE_URL}/api/users/1`);
    expect(userResponse.status).toBe(200);
    expect(userResponse.data.responseTime).toBeGreaterThan(100);
  });

  test('should demonstrate circuit breaker', async () => {
    // Start high error rate experiment
    const experiment = {
      experimentId: 'test-errors',
      targetService: 'database-service',
      type: 'errors',
      parameters: { errorRate: 0.8 },
      duration: 5
    };

    await axios.post(`${CHAOS_URL}/chaos/start`, experiment);

    // Make multiple requests to trigger circuit breaker
    for (let i = 0; i < 10; i++) {
      try {
        await axios.get(`${BASE_URL}/api/users/1`);
      } catch (error) {
        // Expected to fail sometimes
      }
    }

    // Check circuit breaker status
    const cbResponse = await axios.get(`${BASE_URL}/circuit-breakers`);
    expect(cbResponse.status).toBe(200);
  });
});
