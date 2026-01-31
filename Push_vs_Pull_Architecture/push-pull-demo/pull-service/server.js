const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());

let requestCount = 0;
let dataFetched = 0;
let emptyPolls = 0;

app.get('/poll', async (req, res) => {
  requestCount++;
  const since = req.query.since ? parseInt(req.query.since) : 0;
  
  try {
    const response = await axios.get(`http://data-generator:3001/latest?since=${since}`);
    const { data, latest } = response.data;
    
    if (data.length === 0) {
      emptyPolls++;
    } else {
      dataFetched += data.length;
    }
    
    console.log(`Poll request: ${data.length} new readings`);
    res.json({ data, latest });
  } catch (error) {
    console.error('Error:', error.message);
    res.status(500).json({ error: 'Failed to fetch data' });
  }
});

app.get('/stats', (req, res) => {
  res.json({
    type: 'pull',
    requestCount,
    dataFetched,
    emptyPolls,
    efficiency: requestCount > 0 ? ((requestCount - emptyPolls) / requestCount * 100).toFixed(1) : 0
  });
});

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.listen(3003, () => console.log('Pull Service running on port 3003'));
