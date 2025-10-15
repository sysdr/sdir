const request = require('supertest');

describe('SLA Design Demo Tests', () => {
  const baseURL = 'http://localhost:3000';
  
  test('Server should be running', async () => {
    const response = await request(baseURL).get('/');
    expect(response.status).toBe(200);
  });
  
  test('SLA status endpoint should return data', async () => {
    const response = await request(baseURL).get('/api/sla-status');
    expect(response.status).toBe(200);
    expect(response.body).toBeDefined();
  });
  
  test('Service request should process successfully', async () => {
    const response = await request(baseURL)
      .post('/api/request')
      .send({ service: 'auth-service', tier: 'standard' });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('success');
    expect(response.body).toHaveProperty('responseTime');
  });
});
