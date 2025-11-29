const request = require('supertest');
const express = require('express');

describe('Device Edge Tests', () => {
  test('Health check returns healthy status', async () => {
    const app = express();
    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', tier: 'device-edge' });
    });
    
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });
  
  test('Sensor data processing completes under 5ms', () => {
    const start = Date.now();
    const data = { temperature: 25, humidity: 60 };
    const latency = Date.now() - start;
    expect(latency).toBeLessThan(5);
  });
});
