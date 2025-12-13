const POD_NAME = process.env.POD_NAME || 'unknown';
const APP_URL = 'http://localhost:3000';
const AGGREGATOR_URL = process.env.AGGREGATOR_URL || 'http://aggregator-service:4000';

async function reportStatus() {
  try {
    const response = await fetch(`${APP_URL}/api/status`);
    const status = await response.json();
    
    await fetch(`${AGGREGATOR_URL}/report`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(status)
    });
  } catch (error) {
    console.error('Failed to report status:', error.message);
  }
}

// Report every 2 seconds
setInterval(reportStatus, 2000);
console.log(`Reporter started for pod ${POD_NAME}`);
