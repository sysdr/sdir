-- Demo DB setup for connection storm article
CREATE TABLE IF NOT EXISTS requests (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  duration_ms INTEGER,
  service TEXT,
  status TEXT
);

CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name TEXT,
  price DECIMAL(10,2),
  inventory INTEGER
);

INSERT INTO products (name, price, inventory)
SELECT 
  'Product ' || i,
  (random() * 100)::DECIMAL(10,2),
  (random() * 1000)::INTEGER
FROM generate_series(1, 500) AS i;

CREATE OR REPLACE VIEW connection_stats AS
SELECT 
  state,
  count(*) as count,
  MAX(EXTRACT(EPOCH FROM (NOW() - state_change))) as max_age_seconds
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state;

CREATE OR REPLACE FUNCTION slow_query(ms INTEGER) RETURNS TEXT AS $$
BEGIN
  PERFORM pg_sleep(ms / 1000.0);
  RETURN 'done';
END;
$$ LANGUAGE plpgsql;

GRANT ALL ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_user;
