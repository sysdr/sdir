const express = require('express');
const axios = require('axios');
const path = require('path');

const app = express();
app.use(express.static('public'));
app.use(express.json());

// Server configurations
const servers = [
    { name: 'healthy-server', url: 'http://healthy-server:5000', type: 'healthy' },
    { name: 'zombie-server', url: 'http://zombie-server:5000', type: 'zombie' },
    { name: 'dead-server', url: 'http://dead-server:5000', type: 'dead' }
];

// Health check both shallow and deep
async function checkServerHealth(server) {
    try {
        const shallowStart = Date.now();
        const shallow = await axios.get(`${server.url}/health`, { timeout: 2000 });
        const shallowTime = Date.now() - shallowStart;

        const deepStart = Date.now();
        const deep = await axios.get(`${server.url}/health/deep`, { timeout: 5000 });
        const deepTime = Date.now() - deepStart;

        const stats = await axios.get(`${server.url}/api/stats`, { timeout: 2000 });

        return {
            name: server.name,
            type: server.type,
            shallow: { status: shallow.status, time: shallowTime, data: shallow.data },
            deep: { status: deep.status, time: deepTime, data: deep.data },
            stats: stats.data,
            overall: shallow.status === 200 && deep.status === 200 ? 'healthy' : 'unhealthy'
        };
    } catch (error) {
        return {
            name: server.name,
            type: server.type,
            shallow: { status: 'error', error: error.message },
            deep: { status: 'error', error: error.message },
            stats: { error: error.message },
            overall: 'dead'
        };
    }
}

// Load test endpoints
async function loadTest(endpoint, requests = 10) {
    const results = [];
    const promises = [];

    for (let i = 0; i < requests; i++) {
        promises.push(
            axios.get(endpoint, { timeout: 5000 })
                .then(response => ({ success: true, time: response.headers['response-time'] || 'unknown' }))
                .catch(error => ({ success: false, error: error.message }))
        );
    }

    const responses = await Promise.all(promises);
    return {
        total: requests,
        successful: responses.filter(r => r.success).length,
        failed: responses.filter(r => !r.success).length,
        success_rate: (responses.filter(r => r.success).length / requests * 100).toFixed(2)
    };
}

// API Routes
app.get('/api/health-status', async (req, res) => {
    const healthResults = await Promise.all(servers.map(checkServerHealth));
    res.json(healthResults);
});

app.post('/api/load-test/shallow', async (req, res) => {
    const { requests = 20 } = req.body;
    const result = await loadTest('http://nginx:80/api/shallow/api/process', requests);
    res.json(result);
});

app.post('/api/load-test/smart', async (req, res) => {
    const { requests = 20 } = req.body;
    const result = await loadTest('http://nginx:80/api/smart/api/process', requests);
    res.json(result);
});

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Dashboard running on port ${PORT}`);
});
