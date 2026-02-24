-- Initial schema: legacy table with full_name column
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed data: 50,000 rows
INSERT INTO users (full_name, email)
SELECT
  (ARRAY['Alice','Bob','Carol','David','Eve','Frank','Grace','Henry','Iris','Jack'])[floor(random()*10+1)::int]
  || ' ' ||
  (ARRAY['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Wilson','Moore'])[floor(random()*10+1)::int],
  'user' || gs || '@example.com'
FROM generate_series(1, 50000) gs
ON CONFLICT DO NOTHING;

-- Migration tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  phase VARCHAR(50) NOT NULL,
  description TEXT NOT NULL,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  rows_processed INT DEFAULT 0,
  status VARCHAR(20) DEFAULT 'pending'
);

-- Lock events tracking
CREATE TABLE IF NOT EXISTS lock_events (
  id SERIAL PRIMARY KEY,
  event_type VARCHAR(100),
  duration_ms FLOAT,
  phase VARCHAR(50),
  occurred_at TIMESTAMPTZ DEFAULT NOW()
);

-- Track migration state
CREATE TABLE IF NOT EXISTS migration_state (
  key VARCHAR(100) PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO migration_state (key, value) VALUES
  ('current_phase', 'pre_migration'),
  ('backfill_progress', '0'),
  ('total_rows', '50000'),
  ('dual_write_active', 'false'),
  ('contract_complete', 'false')
ON CONFLICT DO NOTHING;

-- Helper function to simulate lock timing
CREATE OR REPLACE FUNCTION record_lock_event(p_type VARCHAR, p_duration FLOAT, p_phase VARCHAR)
RETURNS void AS $$
BEGIN
  INSERT INTO lock_events (event_type, duration_ms, phase) VALUES (p_type, p_duration, p_phase);
END;
$$ LANGUAGE plpgsql;
