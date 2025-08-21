const request = require('supertest');
const { app, regionManager } = require('../src/app');

describe('Multi-Region Failover API', () => {
  test('GET /api/health should return region health', async () => {
    const response = await request(app)
      .get('/api/health')
      .expect(200);
    
    expect(response.body).toHaveProperty('region');
    expect(response.body).toHaveProperty('status');
    expect(response.body.status).toBe('healthy');
  });

  test('GET /api/status should return all regions status', async () => {
    const response = await request(app)
      .get('/api/status')
      .expect(200);
    
    expect(response.body).toHaveProperty('regions');
    expect(response.body).toHaveProperty('currentPrimary');
    expect(Array.isArray(response.body.regions)).toBe(true);
  });

  test('POST /api/simulate-failure should trigger failover', async () => {
    const response = await request(app)
      .post('/api/simulate-failure/us-west-2')
      .expect(200);
    
    expect(response.body).toHaveProperty('message');
  });

  test('Failover should change primary region when primary fails', async () => {
    // Simulate primary region failure
    await regionManager.simulateRegionFailure('us-east-1');
    
    const status = regionManager.getRegionStatus();
    expect(status.currentPrimary).not.toBe('us-east-1');
  },10000);
});
