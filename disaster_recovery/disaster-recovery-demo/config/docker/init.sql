-- Initialize database for disaster recovery demo
CREATE TABLE IF NOT EXISTS inventory (
    id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    customer_id VARCHAR(100) NOT NULL,
    product_id INTEGER REFERENCES inventory(id),
    quantity INTEGER NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    order_status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS backup_log (
    id SERIAL PRIMARY KEY,
    service_tier INTEGER NOT NULL,
    backup_type VARCHAR(50) NOT NULL,
    backup_size_bytes BIGINT,
    backup_duration_ms INTEGER,
    success BOOLEAN NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO inventory (product_name, quantity) VALUES 
    ('Premium Widget', 100),
    ('Standard Widget', 500),
    ('Economy Widget', 1000);

INSERT INTO orders (customer_id, product_id, quantity, total_amount) VALUES 
    ('customer_001', 1, 2, 59.98),
    ('customer_002', 2, 5, 149.95),
    ('customer_003', 3, 10, 199.90);
