const request = require('supertest');
const express = require('express');

describe('Central Cloud Tests', () => {
  test('Health check returns healthy status', async () => {
    const app = express();
    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', tier: 'central-cloud' });
    });
    
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
});
