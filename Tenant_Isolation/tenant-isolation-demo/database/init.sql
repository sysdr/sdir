-- Enable Row Level Security
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create tenants table
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    rate_limit INTEGER DEFAULT 100,
    max_users INTEGER DEFAULT 10
);

-- Create users table with tenant isolation
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    api_key VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, email)
);

-- Create tasks table with tenant isolation
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    user_id UUID NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create application user for API
CREATE USER application_user WITH PASSWORD 'app_secret';
GRANT CONNECT ON DATABASE multitenant_db TO application_user;
GRANT USAGE ON SCHEMA public TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO application_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO application_user;

-- Enable RLS on all tables
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for tenant isolation
CREATE POLICY tenant_isolation_users ON users
    FOR ALL TO application_user
    USING (tenant_id = current_setting('app.tenant_id')::UUID);

CREATE POLICY tenant_isolation_tasks ON tasks
    FOR ALL TO application_user
    USING (tenant_id = current_setting('app.tenant_id')::UUID);

-- Insert sample tenants
INSERT INTO tenants (id, name, rate_limit, max_users) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 'acme-corp', 200, 20),
    ('550e8400-e29b-41d4-a716-446655440002', 'startup-inc', 50, 5),
    ('550e8400-e29b-41d4-a716-446655440003', 'enterprise-ltd', 1000, 100);

-- Insert sample users
INSERT INTO users (tenant_id, email, name, api_key) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 'john@acme-corp.com', 'John Doe', 'acme-key-123'),
    ('550e8400-e29b-41d4-a716-446655440002', 'jane@startup-inc.com', 'Jane Smith', 'startup-key-456'),
    ('550e8400-e29b-41d4-a716-446655440003', 'bob@enterprise-ltd.com', 'Bob Wilson', 'enterprise-key-789');

-- Insert sample tasks
INSERT INTO tasks (tenant_id, user_id, title, description) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 
     (SELECT id FROM users WHERE email = 'john@acme-corp.com'), 
     'Setup CI/CD Pipeline', 'Configure automated deployment'),
    ('550e8400-e29b-41d4-a716-446655440002', 
     (SELECT id FROM users WHERE email = 'jane@startup-inc.com'), 
     'Launch MVP', 'Deploy minimum viable product'),
    ('550e8400-e29b-41d4-a716-446655440003', 
     (SELECT id FROM users WHERE email = 'bob@enterprise-ltd.com'), 
     'Security Audit', 'Conduct quarterly security review');
