-- Create replication user
CREATE ROLE replicator WITH REPLICATION PASSWORD 'password' LOGIN;

-- Create health check table
CREATE TABLE IF NOT EXISTS health_check (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    node_name VARCHAR(50)
);

-- Create transaction log table
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    amount DECIMAL(10,2),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20)
);

-- Insert initial data
INSERT INTO transactions (amount, status) VALUES (100.50, 'completed');
INSERT INTO transactions (amount, status) VALUES (250.00, 'completed');
