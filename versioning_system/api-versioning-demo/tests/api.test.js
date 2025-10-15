const request = require('supertest');
const app = require('../src/server');

describe('API Versioning', () => {
  test('URI path versioning v1', async () => {
    const response = await request(app)
      .get('/api/v1/users')
      .expect(200);
    
    expect(response.body.version).toBe('1.0');
    expect(response.body.users).toBeDefined();
    expect(response.body.users[0]).toHaveProperty('name');
    expect(response.body.users[0]).not.toHaveProperty('age');
  });
  
  test('URI path versioning v2', async () => {
    const response = await request(app)
      .get('/api/v2/users')
      .expect(200);
    
    expect(response.body.version).toBe('2.0');
    expect(response.body.users[0]).toHaveProperty('full_name');
    expect(response.body.users[0]).toHaveProperty('age');
  });
  
  test('Header versioning', async () => {
    const response = await request(app)
      .get('/api/users')
      .set('API-Version', '2')
      .expect(200);
    
    expect(response.body.version).toBe('2.0');
  });
  
  test('Content negotiation', async () => {
    const response = await request(app)
      .get('/api/users')
      .set('Accept', 'application/json;version=3')
      .expect(200);
    
    expect(response.body.version).toBe('3.0');
    expect(response.body.data[0]).toHaveProperty('user_id');
    expect(response.body.data[0]).toHaveProperty('profile');
  });
  
  test('Version detection fallback', async () => {
    const response = await request(app)
      .get('/api/users')
      .expect(200);
    
    expect(response.body.version).toBe('1.0');
  });
  
  test('Health check', async () => {
    const response = await request(app)
      .get('/health')
      .expect(200);
    
    expect(response.body.status).toBe('healthy');
  });
});
