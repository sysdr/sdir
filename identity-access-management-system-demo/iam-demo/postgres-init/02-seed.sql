-- Insert default roles
INSERT INTO roles (name, description) VALUES
('admin', 'Administrator with full access'),
('user', 'Regular user with basic access'),
('viewer', 'Read-only access');

-- Insert permissions
INSERT INTO permissions (name, resource, action) VALUES
('read_documents', 'documents', 'read'),
('write_documents', 'documents', 'write'),
('delete_documents', 'documents', 'delete'),
('read_users', 'users', 'read'),
('manage_users', 'users', 'write');

-- Assign permissions to roles
-- Admin gets all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.name = 'admin';

-- User gets read/write documents
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'user' AND p.name IN ('read_documents', 'write_documents');

-- Viewer gets read-only
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'viewer' AND p.name = 'read_documents';

-- Create sample users (password: 'password123' - bcrypt hash)
INSERT INTO users (username, email, password_hash) VALUES
('admin', 'admin@example.com', '$2b$10$rXKhF5xhF8Y5nLqN5sLXxOGZKdvBxX7V3qJYZxZqN5xX7V3qJYZxZ'),
('alice', 'alice@example.com', '$2b$10$rXKhF5xhF8Y5nLqN5sLXxOGZKdvBxX7V3qJYZxZqN5xX7V3qJYZxZ'),
('bob', 'bob@example.com', '$2b$10$rXKhF5xhF8Y5nLqN5sLXxOGZKdvBxX7V3qJYZxZqN5xX7V3qJYZxZ');

-- Assign roles to users
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r WHERE u.username = 'admin' AND r.name = 'admin';

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r WHERE u.username = 'alice' AND r.name = 'user';

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r WHERE u.username = 'bob' AND r.name = 'viewer';

-- Sample ABAC policy: Allow document access only during business hours
INSERT INTO abac_policies (name, resource_type, conditions, effect, priority) VALUES
('business_hours_policy', 'documents', 
 '{"time_of_day": {"start": "09:00", "end": "17:00"}, "days": ["Mon", "Tue", "Wed", "Thu", "Fri"]}', 
 'allow', 10);

-- Sample OAuth client
INSERT INTO oauth_clients (client_id, client_secret, redirect_uris, name) VALUES
('demo-client', 'demo-secret', ARRAY['http://localhost:8080/callback'], 'Demo Application');
