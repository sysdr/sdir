const express = require('express');
const app = express();

let sensorData = [];
let dataId = 1;

// Generate realistic sensor data
function generateReading() {
  const sensors = ['temperature', 'humidity', 'pressure'];
  return {
    id: dataId++,
    sensor: sensors[Math.floor(Math.random() * sensors.length)],
    value: (Math.random() * 100).toFixed(2),
    timestamp: new Date().toISOString()
  };
}

// Generate data every 500ms
setInterval(() => {
  const reading = generateReading();
  sensorData.push(reading);
  
  // Keep last 100 readings
  if (sensorData.length > 100) {
    sensorData.shift();
  }
  
  console.log(`Generated: ${reading.sensor}=${reading.value}`);
}, 500);

app.get('/latest', (req, res) => {
  const since = req.query.since ? parseInt(req.query.since) : 0;
  const newData = sensorData.filter(d => d.id > since);
  res.json({ data: newData, latest: dataId - 1 });
});

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.listen(3001, () => console.log('Data Generator running on port 3001'));
