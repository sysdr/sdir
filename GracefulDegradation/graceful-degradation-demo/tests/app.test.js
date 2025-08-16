const request = require('supertest');
const app = require('../src/app');

describe('Graceful Degradation vs Fail Fast Tests', () => {
  
  test('Health endpoint should return system status', async () => {
    const response = await request(app)
      .get('/health')
      .expect(200);
    
    expect(response.body).toHaveProperty('status', 'healthy');
    expect(response.body).toHaveProperty('services');
  });
  
  test('Recommendations should gracefully degrade when service fails', async () => {
    // First disable the recommendation service
    await request(app)
      .post('/admin/service/recommendation/toggle')
      .expect(200);
    
    const response = await request(app)
      .get('/api/recommendations/user123')
      .expect(200);
    
    expect(response.body.success).toBe(true);
    expect(response.body.degraded).toBe(true);
    expect(response.body.fallback).toBeDefined();
  });
  
  test('Payment should fail fast with invalid input', async () => {
    const response = await request(app)
      .post('/api/payment')
      .send({
        amount: -100, // Invalid amount
        currency: 'USD',
        cardToken: 'tok_test'
      })
      .expect(400);
    
    expect(response.body.success).toBe(false);
    expect(response.body.failFast).toBe(true);
    expect(response.body.error).toContain('Invalid amount');
  });
  
  test('Payment should fail fast when service is unhealthy', async () => {
    // Disable payment service
    await request(app)
      .post('/admin/service/payment/toggle')
      .expect(200);
    
    const response = await request(app)
      .post('/api/payment')
      .send({
        amount: 100,
        currency: 'USD',
        cardToken: 'tok_test_123'
      })
      .expect(503);
    
    expect(response.body.success).toBe(false);
    expect(response.body.failFast).toBe(true);
  });
  
  test('Circuit breaker status should be accessible', async () => {
    const response = await request(app)
      .get('/circuit-breaker/status')
      .expect(200);
    
    expect(response.body).toHaveProperty('primary');
    expect(response.body).toHaveProperty('recommendation');
  });
  
});
