-- Database initialization script
CREATE TABLE IF NOT EXISTS demo_data (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO demo_data (data) 
SELECT 'Sample data record ' || generate_series(1, 1000);

-- Create indexes for performance testing
CREATE INDEX IF NOT EXISTS idx_demo_data_created_at ON demo_data(created_at);
CREATE INDEX IF NOT EXISTS idx_demo_data_data ON demo_data(data);
