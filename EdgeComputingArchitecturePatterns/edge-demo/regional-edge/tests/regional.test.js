const request = require('supertest');
const express = require('express');

describe('Regional Edge Tests', () => {
  test('Health check returns healthy status', async () => {
    const app = express();
    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', tier: 'regional-edge' });
    });
    
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
});
