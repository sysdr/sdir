CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    transaction_id VARCHAR(50) UNIQUE NOT NULL,
    user_id VARCHAR(50) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    merchant VARCHAR(100),
    device_id VARCHAR(100),
    ip_address VARCHAR(50),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    risk_score INTEGER,
    decision VARCHAR(20),
    features JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_id ON transactions(user_id);
CREATE INDEX idx_device_id ON transactions(device_id);
CREATE INDEX idx_timestamp ON transactions(timestamp DESC);
CREATE INDEX idx_decision ON transactions(decision);

CREATE TABLE fraud_patterns (
    id SERIAL PRIMARY KEY,
    pattern_type VARCHAR(50),
    user_id VARCHAR(50),
    device_id VARCHAR(100),
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    severity VARCHAR(20),
    details JSONB
);

CREATE TABLE user_graph (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50),
    connected_user_id VARCHAR(50),
    connection_type VARCHAR(50),
    risk_weight DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
