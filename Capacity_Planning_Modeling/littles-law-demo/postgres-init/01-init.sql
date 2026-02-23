CREATE TABLE IF NOT EXISTS requests (
  id SERIAL PRIMARY KEY,
  layer VARCHAR(20),
  arrived_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  latency_ms INTEGER
);

CREATE TABLE IF NOT EXISTS metrics_snapshot (
  id SERIAL PRIMARY KEY,
  captured_at TIMESTAMPTZ DEFAULT NOW(),
  layer VARCHAR(20),
  lambda_rps NUMERIC(10,2),
  w_ms NUMERIC(10,2),
  l_concurrent NUMERIC(10,2),
  pool_limit INTEGER,
  utilization_pct NUMERIC(5,2)
);

CREATE INDEX idx_requests_layer ON requests(layer);
CREATE INDEX idx_requests_arrived ON requests(arrived_at);
