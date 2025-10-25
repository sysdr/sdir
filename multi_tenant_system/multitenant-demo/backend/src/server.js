const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');

const { DatabaseManager } = require('./services/DatabaseManager');
const { TenantMiddleware } = require('./middleware/TenantMiddleware');
const { MetricsCollector } = require('./services/MetricsCollector');

const app = express();
const PORT = process.env.PORT || 8080;

// Initialize services
const dbManager = new DatabaseManager();
const metricsCollector = new MetricsCollector();

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());

// Rate limiting per tenant
const createTenantRateLimit = (windowMs = 15 * 60 * 1000, max = 100) => {
    return rateLimit({
        windowMs,
        max,
        keyGenerator: (req) => `${req.tenantId || 'anonymous'}`,
        message: { error: 'Rate limit exceeded for tenant' }
    });
};

app.use(createTenantRateLimit());

// Tenant middleware
app.use(TenantMiddleware(dbManager));

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Tenant management endpoints
app.get('/api/tenants', async (req, res) => {
    try {
        const tenants = await dbManager.getAllTenants();
        res.json(tenants);
    } catch (error) {
        console.error('Error fetching tenants:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.get('/api/tenants/:tenantId/stats', async (req, res) => {
    try {
        const { tenantId } = req.params;
        const stats = await dbManager.getTenantStats(tenantId);
        res.json(stats);
    } catch (error) {
        console.error('Error fetching tenant stats:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// User management (tenant-scoped)
app.get('/api/users', async (req, res) => {
    try {
        const users = await dbManager.getUsers(req.tenantId);
        res.json(users);
    } catch (error) {
        console.error('Error fetching users:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/api/users', async (req, res) => {
    try {
        const user = await dbManager.createUser(req.tenantId, req.body);
        metricsCollector.recordUserCreated(req.tenantId);
        res.status(201).json(user);
    } catch (error) {
        console.error('Error creating user:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Order management (tenant-scoped)
app.get('/api/orders', async (req, res) => {
    try {
        const orders = await dbManager.getOrders(req.tenantId);
        res.json(orders);
    } catch (error) {
        console.error('Error fetching orders:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/api/orders', async (req, res) => {
    try {
        const order = await dbManager.createOrder(req.tenantId, req.body);
        metricsCollector.recordOrderCreated(req.tenantId);
        res.status(201).json(order);
    } catch (error) {
        console.error('Error creating order:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Metrics endpoint
app.get('/api/metrics', async (req, res) => {
    try {
        const metrics = await metricsCollector.getAllMetrics();
        res.json(metrics);
    } catch (error) {
        console.error('Error fetching metrics:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Tenant isolation test endpoint
app.post('/api/test-isolation', async (req, res) => {
    try {
        const results = await dbManager.testTenantIsolation();
        res.json(results);
    } catch (error) {
        console.error('Error testing isolation:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Initialize database schemas and data
async function initializeDatabase() {
    try {
        console.log('🔧 Initializing database schemas...');
        
        // Create tenant schema for Pattern 2 (separate schema)
        await dbManager.createTenantSchema('22222222-2222-2222-2222-222222222222');
        
        // Create tables in separate database for Pattern 3
        const tenant1Client = await dbManager.tenant1Pool.connect();
        try {
            await tenant1Client.query(`
                CREATE TABLE IF NOT EXISTS users (
                    id SERIAL PRIMARY KEY,
                    tenant_id UUID NOT NULL,
                    username VARCHAR(255) NOT NULL,
                    email VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            `);
            
            await tenant1Client.query(`
                CREATE TABLE IF NOT EXISTS orders (
                    id SERIAL PRIMARY KEY,
                    tenant_id UUID NOT NULL,
                    user_id INTEGER REFERENCES users(id),
                    product_name VARCHAR(255) NOT NULL,
                    amount DECIMAL(10,2) NOT NULL,
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            `);
            
            // Insert sample data for Pattern 3
            await tenant1Client.query(`
                INSERT INTO users (tenant_id, username, email) VALUES 
                ('33333333-3333-3333-3333-333333333333', 'charlie_gamma', 'charlie@gamma.com'),
                ('33333333-3333-3333-3333-333333333333', 'diana_gamma', 'diana@gamma.com')
                ON CONFLICT DO NOTHING
            `);
            
            await tenant1Client.query(`
                INSERT INTO orders (tenant_id, user_id, product_name, amount) 
                SELECT '33333333-3333-3333-3333-333333333333', u.id, 'Product C', 149.99
                FROM users u WHERE u.tenant_id = '33333333-3333-3333-3333-333333333333' 
                AND NOT EXISTS (SELECT 1 FROM orders WHERE tenant_id = '33333333-3333-3333-3333-333333333333')
                LIMIT 1
            `);
            
            console.log('✅ Pattern 3 (separate DB) tables created and seeded');
        } finally {
            tenant1Client.release();
        }
        
        console.log('✅ Database initialization complete');
    } catch (error) {
        console.error('❌ Database initialization failed:', error);
    }
}

// Initialize database and start server
initializeDatabase().then(() => {
    app.listen(PORT, () => {
        console.log(`🚀 Multi-tenant backend running on port ${PORT}`);
    });
});

module.exports = app;
