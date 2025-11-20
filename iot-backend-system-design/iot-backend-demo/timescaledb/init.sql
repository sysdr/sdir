CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS device_telemetry (
    time TIMESTAMPTZ NOT NULL,
    device_id VARCHAR(50) NOT NULL,
    metric_name VARCHAR(50) NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    metadata JSONB
);

SELECT create_hypertable('device_telemetry', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_device_telemetry_device_id ON device_telemetry (device_id, time DESC);

CREATE TABLE IF NOT EXISTS device_registry (
    device_id VARCHAR(50) PRIMARY KEY,
    device_type VARCHAR(50) NOT NULL,
    desired_state JSONB DEFAULT '{}',
    reported_state JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    last_seen TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_commands (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    command_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    executed_at TIMESTAMPTZ
);

-- Continuous aggregate for hourly downsampling
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_id,
    metric_name,
    AVG(metric_value) AS avg_value,
    MIN(metric_value) AS min_value,
    MAX(metric_value) AS max_value,
    COUNT(*) AS sample_count
FROM device_telemetry
GROUP BY bucket, device_id, metric_name
WITH NO DATA;

SELECT add_continuous_aggregate_policy('device_telemetry_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE);

-- Retention policy: keep raw data for 7 days
SELECT add_retention_policy('device_telemetry', INTERVAL '7 days', if_not_exists => TRUE);
