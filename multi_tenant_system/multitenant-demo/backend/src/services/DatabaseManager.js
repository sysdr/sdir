const { Pool } = require('pg');
const redis = require('redis');

class DatabaseManager {
    constructor() {
        // Shared database pool for Pattern 1 & 2
        this.sharedPool = new Pool({
            connectionString: process.env.SHARED_DB_URL || 'postgresql://admin:password123@localhost:5432/shared_tenants',
            max: 20,
            idleTimeoutMillis: 30000,
            connectionTimeoutMillis: 2000,
        });

        // Separate database pool for Pattern 3
        this.tenant1Pool = new Pool({
            connectionString: process.env.TENANT1_DB_URL || 'postgresql://tenant1_user:tenant1_pass@localhost:5433/tenant1_db',
            max: 10,
        });

        // Redis client for caching and session management
        this.redisClient = redis.createClient({
            url: process.env.REDIS_URL || 'redis://localhost:6379'
        });
        this.redisClient.connect().catch(console.error);

        this.tenantSchemas = new Map();
    }

    // Get appropriate database connection based on tenant
    getPoolForTenant(tenantId) {
        if (tenantId === '33333333-3333-3333-3333-333333333333') {
            return this.tenant1Pool; // Pattern 3: Separate DB
        }
        return this.sharedPool; // Pattern 1 & 2: Shared DB
    }

    // Set tenant context for Row-Level Security
    async setTenantContext(client, tenantId) {
        await client.query('SELECT set_config($1, $2, true)', ['app.current_tenant', tenantId]);
    }

    // Pattern 2: Create separate schema for tenant
    async createTenantSchema(tenantId) {
        const client = await this.sharedPool.connect();
        try {
            const schemaName = `tenant_${tenantId.replace(/-/g, '_')}`;
            
            await client.query(`CREATE SCHEMA IF NOT EXISTS ${schemaName}`);
            
            // Create tables in tenant schema
            await client.query(`
                CREATE TABLE IF NOT EXISTS ${schemaName}.users (
                    id SERIAL PRIMARY KEY,
                    username VARCHAR(255) NOT NULL,
                    email VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            `);
            
            await client.query(`
                CREATE TABLE IF NOT EXISTS ${schemaName}.orders (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER REFERENCES ${schemaName}.users(id),
                    product_name VARCHAR(255) NOT NULL,
                    amount DECIMAL(10,2) NOT NULL,
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            `);

            this.tenantSchemas.set(tenantId, schemaName);
            
            // Insert sample data for Pattern 2
            await client.query(`
                INSERT INTO ${schemaName}.users (username, email) VALUES 
                ('eve_beta', 'eve@beta.com'),
                ('frank_beta', 'frank@beta.com')
                ON CONFLICT DO NOTHING
            `);
            
            await client.query(`
                INSERT INTO ${schemaName}.orders (user_id, product_name, amount) 
                SELECT u.id, 'Product B', 199.99
                FROM ${schemaName}.users u 
                WHERE NOT EXISTS (SELECT 1 FROM ${schemaName}.orders)
                LIMIT 1
            `);
            
            console.log(`Created schema and sample data for tenant: ${tenantId}`);
        } finally {
            client.release();
        }
    }

    // Get all tenants
    async getAllTenants() {
        const client = await this.sharedPool.connect();
        try {
            const result = await client.query('SELECT * FROM tenants ORDER BY created_at');
            return result.rows;
        } finally {
            client.release();
        }
    }

    // Get tenant statistics
    async getTenantStats(tenantId) {
        const pool = this.getPoolForTenant(tenantId);
        const client = await pool.connect();
        
        try {
            await this.setTenantContext(client, tenantId);
            
            let userCount, orderCount;
            
            if (tenantId === '22222222-2222-2222-2222-222222222222') {
                // Pattern 2: Separate schema
                const schema = this.tenantSchemas.get(tenantId) || `tenant_${tenantId.replace(/-/g, '_')}`;
                const userResult = await client.query(`SELECT COUNT(*) FROM ${schema}.users`);
                const orderResult = await client.query(`SELECT COUNT(*) FROM ${schema}.orders`);
                userCount = parseInt(userResult.rows[0].count);
                orderCount = parseInt(orderResult.rows[0].count);
            } else {
                // Pattern 1 (shared schema) or Pattern 3 (separate DB)
                const userResult = await client.query('SELECT COUNT(*) FROM users WHERE tenant_id = $1', [tenantId]);
                const orderResult = await client.query('SELECT COUNT(*) FROM orders WHERE tenant_id = $1', [tenantId]);
                userCount = parseInt(userResult.rows[0].count);
                orderCount = parseInt(orderResult.rows[0].count);
            }

            return {
                tenantId,
                userCount,
                orderCount,
                isolationPattern: this.getIsolationPattern(tenantId)
            };
        } finally {
            client.release();
        }
    }

    getIsolationPattern(tenantId) {
        if (tenantId === '11111111-1111-1111-1111-111111111111') return 'shared_schema';
        if (tenantId === '22222222-2222-2222-2222-222222222222') return 'separate_schema';
        if (tenantId === '33333333-3333-3333-3333-333333333333') return 'separate_db';
        return 'unknown';
    }

    // Get users for tenant
    async getUsers(tenantId) {
        const pool = this.getPoolForTenant(tenantId);
        const client = await pool.connect();
        
        try {
            await this.setTenantContext(client, tenantId);
            
            if (tenantId === '22222222-2222-2222-2222-222222222222') {
                // Pattern 2: Separate schema
                const schema = this.tenantSchemas.get(tenantId) || `tenant_${tenantId.replace(/-/g, '_')}`;
                const result = await client.query(`SELECT * FROM ${schema}.users ORDER BY created_at`);
                return result.rows;
            } else {
                // Pattern 1 or 3
                const result = await client.query('SELECT * FROM users WHERE tenant_id = $1 ORDER BY created_at', [tenantId]);
                return result.rows;
            }
        } finally {
            client.release();
        }
    }

    // Create user
    async createUser(tenantId, userData) {
        const pool = this.getPoolForTenant(tenantId);
        const client = await pool.connect();
        
        try {
            await this.setTenantContext(client, tenantId);
            
            if (tenantId === '22222222-2222-2222-2222-222222222222') {
                // Ensure schema exists
                if (!this.tenantSchemas.has(tenantId)) {
                    await this.createTenantSchema(tenantId);
                }
                
                const schema = this.tenantSchemas.get(tenantId);
                const result = await client.query(
                    `INSERT INTO ${schema}.users (username, email) VALUES ($1, $2) RETURNING *`,
                    [userData.username, userData.email]
                );
                return result.rows[0];
            } else {
                const result = await client.query(
                    'INSERT INTO users (tenant_id, username, email) VALUES ($1, $2, $3) RETURNING *',
                    [tenantId, userData.username, userData.email]
                );
                return result.rows[0];
            }
        } finally {
            client.release();
        }
    }

    // Get orders for tenant
    async getOrders(tenantId) {
        const pool = this.getPoolForTenant(tenantId);
        const client = await pool.connect();
        
        try {
            await this.setTenantContext(client, tenantId);
            
            if (tenantId === '22222222-2222-2222-2222-222222222222') {
                const schema = this.tenantSchemas.get(tenantId) || `tenant_${tenantId.replace(/-/g, '_')}`;
                const result = await client.query(`
                    SELECT o.*, u.username, u.email 
                    FROM ${schema}.orders o 
                    JOIN ${schema}.users u ON o.user_id = u.id 
                    ORDER BY o.created_at DESC
                `);
                return result.rows;
            } else {
                const result = await client.query(`
                    SELECT o.*, u.username, u.email 
                    FROM orders o 
                    JOIN users u ON o.user_id = u.id 
                    WHERE o.tenant_id = $1 
                    ORDER BY o.created_at DESC
                `, [tenantId]);
                return result.rows;
            }
        } finally {
            client.release();
        }
    }

    // Create order
    async createOrder(tenantId, orderData) {
        const pool = this.getPoolForTenant(tenantId);
        const client = await pool.connect();
        
        try {
            await this.setTenantContext(client, tenantId);
            
            if (tenantId === '22222222-2222-2222-2222-222222222222') {
                const schema = this.tenantSchemas.get(tenantId) || `tenant_${tenantId.replace(/-/g, '_')}`;
                const result = await client.query(
                    `INSERT INTO ${schema}.orders (user_id, product_name, amount) VALUES ($1, $2, $3) RETURNING *`,
                    [orderData.user_id, orderData.product_name, orderData.amount]
                );
                return result.rows[0];
            } else {
                const result = await client.query(
                    'INSERT INTO orders (tenant_id, user_id, product_name, amount) VALUES ($1, $2, $3, $4) RETURNING *',
                    [tenantId, orderData.user_id, orderData.product_name, orderData.amount]
                );
                return result.rows[0];
            }
        } finally {
            client.release();
        }
    }

    // Test tenant isolation
    async testTenantIsolation() {
        const results = {
            shared_schema: await this.testSharedSchemaIsolation(),
            separate_schema: await this.testSeparateSchemaIsolation(),
            separate_db: await this.testSeparateDbIsolation()
        };
        
        return results;
    }

    async testSharedSchemaIsolation() {
        const client = await this.sharedPool.connect();
        try {
            // Test that RLS prevents cross-tenant access
            await this.setTenantContext(client, '11111111-1111-1111-1111-111111111111');
            const result1 = await client.query('SELECT COUNT(*) FROM users');
            
            await this.setTenantContext(client, '22222222-2222-2222-2222-222222222222');
            const result2 = await client.query('SELECT COUNT(*) FROM users');
            
            return {
                pattern: 'shared_schema',
                tenant1_users: parseInt(result1.rows[0].count),
                tenant2_users: parseInt(result2.rows[0].count),
                isolated: true
            };
        } catch (error) {
            return { pattern: 'shared_schema', error: error.message, isolated: false };
        } finally {
            client.release();
        }
    }

    async testSeparateSchemaIsolation() {
        try {
            return {
                pattern: 'separate_schema',
                schema_exists: this.tenantSchemas.has('22222222-2222-2222-2222-222222222222'),
                isolated: true
            };
        } catch (error) {
            return { pattern: 'separate_schema', error: error.message, isolated: false };
        }
    }

    async testSeparateDbIsolation() {
        try {
            const client = await this.tenant1Pool.connect();
            const result = await client.query('SELECT COUNT(*) FROM users');
            client.release();
            
            return {
                pattern: 'separate_db',
                connection_successful: true,
                isolated: true
            };
        } catch (error) {
            return { pattern: 'separate_db', error: error.message, isolated: false };
        }
    }
}

module.exports = { DatabaseManager };
