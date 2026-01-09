const express = require('express');
const fetch = require('node-fetch');

const app = express();
const FLAG_SERVICE = 'http://flag-service:3000';

async function evaluateFlag(flagId, userId) {
  try {
    const res = await fetch(`${FLAG_SERVICE}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ flagId, userId, context: {} })
    });
    const data = await res.json();
    return data.enabled;
  } catch (error) {
    return false;
  }
}

app.get('/process/:userId', async (req, res) => {
  const { userId } = req.params;
  
  const newFlowEnabled = await evaluateFlag('new-payment-flow', userId);
  
  const processingTime = newFlowEnabled ? 200 : 500;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  res.json({
    service: 'payment',
    userId,
    version: newFlowEnabled ? 'streamlined' : 'legacy',
    processingTime: `${processingTime}ms`
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment' });
});

app.listen(3002, () => console.log('Payment service on port 3002'));
