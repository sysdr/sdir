const express = require('express');
const axios = require('axios');
const path = require('path');

const app = express();
const port = 3000;

const COORDINATOR_URL = process.env.COORDINATOR_URL || 'http://coordinator:8000';

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static('public'));
app.use(express.json());

// Home page
app.get('/', async (req, res) => {
    try {
        const statusResponse = await axios.get(`${COORDINATOR_URL}/status`);
        const systemStatus = statusResponse.data;
        
        res.render('index', { 
            systemStatus,
            coordinatorUrl: COORDINATOR_URL
        });
    } catch (error) {
        res.render('index', { 
            systemStatus: { error: 'Cannot connect to coordinator' },
            coordinatorUrl: COORDINATOR_URL
        });
    }
});

// Start transaction
app.post('/transaction', async (req, res) => {
    try {
        const transactionData = {
            participants: req.body.participants || ['payment-service', 'inventory-service', 'shipping-service'],
            operation_data: req.body.operation_data || {
                amount: 100,
                product: 'laptop',
                quantity: 1,
                shipping_address: '123 Main St, City, State'
            }
        };
        
        const response = await axios.post(`${COORDINATOR_URL}/transaction`, transactionData);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get transaction status
app.get('/transaction/:id', async (req, res) => {
    try {
        const response = await axios.get(`${COORDINATOR_URL}/transaction/${req.params.id}`);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get system status
app.get('/api/status', async (req, res) => {
    try {
        const response = await axios.get(`${COORDINATOR_URL}/status`);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(port, '0.0.0.0', () => {
    console.log(`🌐 Two-Phase Commit UI running at http://localhost:${port}`);
});
