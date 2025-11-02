-- Pattern 1: Shared Database, Shared Schema with tenant_id
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_username_per_tenant UNIQUE(tenant_id, username)
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    user_id INTEGER REFERENCES users(id),
    product_name VARCHAR(255) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pattern 2: Separate Schemas (created dynamically in backend)
-- CREATE SCHEMA tenant_alpha;
-- CREATE SCHEMA tenant_beta;

-- Enable Row-Level Security for enhanced isolation
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Create application role
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_role') THEN
        CREATE ROLE app_role;
    END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_role;

-- Row-Level Security policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_isolation_users') THEN
        CREATE POLICY tenant_isolation_users ON users 
            FOR ALL TO app_role 
            USING (tenant_id = COALESCE(current_setting('app.current_tenant', true)::uuid, tenant_id));
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_isolation_orders') THEN
        CREATE POLICY tenant_isolation_orders ON orders 
            FOR ALL TO app_role 
            USING (tenant_id = COALESCE(current_setting('app.current_tenant', true)::uuid, tenant_id));
    END IF;
END $$;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_tenant_id ON orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);

-- Create tenants table for metadata
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    isolation_pattern VARCHAR(50) NOT NULL, -- 'shared_schema', 'separate_schema', 'separate_db'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    settings JSONB DEFAULT '{}'::jsonb
);

-- Insert demo tenants
INSERT INTO tenants (id, name, isolation_pattern) VALUES 
    ('11111111-1111-1111-1111-111111111111', 'Tenant Alpha (Shared Schema)', 'shared_schema'),
    ('22222222-2222-2222-2222-222222222222', 'Tenant Beta (Separate Schema)', 'separate_schema'),
    ('33333333-3333-3333-3333-333333333333', 'Tenant Gamma (Separate DB)', 'separate_db')
ON CONFLICT (id) DO NOTHING;

-- Insert sample data for Pattern 1 (Shared Schema)
INSERT INTO users (tenant_id, username, email) VALUES 
    ('11111111-1111-1111-1111-111111111111', 'alice_alpha', 'alice@alpha.com'),
    ('11111111-1111-1111-1111-111111111111', 'bob_alpha', 'bob@alpha.com')
ON CONFLICT DO NOTHING;

INSERT INTO orders (tenant_id, user_id, product_name, amount) 
SELECT '11111111-1111-1111-1111-111111111111', u.id, 'Product A', 99.99
FROM users u WHERE u.tenant_id = '11111111-1111-1111-1111-111111111111' 
AND NOT EXISTS (SELECT 1 FROM orders WHERE tenant_id = '11111111-1111-1111-1111-111111111111');
