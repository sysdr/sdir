const request = require('supertest');
const app = require('../server');

describe('API Endpoints', () => {
  test('GET /api/health returns healthy status', async () => {
    const response = await request(app)
      .get('/api/health')
      .expect(200);
    
    expect(response.body.status).toBe('healthy');
  });

  test('GET /api/incidents returns incidents list', async () => {
    const response = await request(app)
      .get('/api/incidents')
      .expect(200);
    
    expect(response.body).toHaveProperty('incidents');
    expect(Array.isArray(response.body.incidents)).toBe(true);
  });
});
