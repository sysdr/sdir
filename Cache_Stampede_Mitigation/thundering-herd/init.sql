CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (id, name, price, description) VALUES
(1, 'Premium Widget', 99.99, 'High-traffic product that commonly causes cache stampedes'),
(2, 'Standard Widget', 49.99, 'Medium-traffic product'),
(3, 'Basic Widget', 19.99, 'Low-traffic product');
