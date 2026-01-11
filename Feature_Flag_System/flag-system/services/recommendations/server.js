const express = require('express');
const fetch = require('node-fetch');

const app = express();
const FLAG_SERVICE = 'http://flag-service:3000';

async function evaluateFlag(flagId, userId) {
  try {
    const res = await fetch(`${FLAG_SERVICE}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        flagId, 
        userId, 
        context: { region: 'US' }
      })
    });
    const data = await res.json();
    return data.enabled;
  } catch (error) {
    return false;
  }
}

app.get('/recommendations/:userId', async (req, res) => {
  const { userId } = req.params;
  
  const v2Enabled = await evaluateFlag('recommendations-v2', userId);
  
  const recommendations = v2Enabled 
    ? ['ML-Powered Item A', 'ML-Powered Item B', 'ML-Powered Item C']
    : ['Standard Item 1', 'Standard Item 2', 'Standard Item 3'];
  
  res.json({
    service: 'recommendations',
    userId,
    engine: v2Enabled ? 'ml-v2' : 'rule-based',
    items: recommendations
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'recommendations' });
});

app.listen(3003, () => console.log('Recommendations service on port 3003'));
