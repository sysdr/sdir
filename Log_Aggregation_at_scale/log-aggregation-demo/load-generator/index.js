/**
 * Log Generator for Article 214 Demo
 * Produces structured JSON logs simulating a microservices environment
 */

const fs = require('fs');
const path = require('path');

const config = JSON.parse(fs.readFileSync('/app/config.json', 'utf8'));

const LOG_DIR = '/var/log/app';
const TRACE_CHARS = 'abcdef0123456789';
const genTraceId = () => Array.from({length: 16}, () => TRACE_CHARS[Math.floor(Math.random() * 16)]).join('');
const genDuration = (min, max) => Math.floor(Math.random() * (max - min) + min);

const ERROR_MESSAGES = [
  'database connection timeout after 5000ms',
  'upstream service returned 503: Service Unavailable',
  'failed to acquire distributed lock: key=session:abc123',
  'redis NOAUTH authentication required',
  'context deadline exceeded: read tcp',
  'ECONNREFUSED: connection refused 127.0.0.1:5432'
];

const WARN_MESSAGES = [
  'slow query detected: 2340ms (threshold: 1000ms)',
  'connection pool utilization at 85%',
  'retry attempt 2/3 for downstream call',
  'cache miss rate elevated: 42% over last 5m',
  'request queue depth: 1847 (warning threshold: 1000)'
];

const INFO_MESSAGES = [
  'request processed successfully',
  'cache hit: user_session',
  'background job completed: 1247 records processed',
  'health check passed',
  'feature flag evaluated: dark_mode=true',
  'payment authorized via provider stripe'
];

function buildLogLine(service, level, userIdAsLabel) {
  const msg = level === 'error'
    ? ERROR_MESSAGES[Math.floor(Math.random() * ERROR_MESSAGES.length)]
    : level === 'warn'
    ? WARN_MESSAGES[Math.floor(Math.random() * WARN_MESSAGES.length)]
    : INFO_MESSAGES[Math.floor(Math.random() * INFO_MESSAGES.length)];

  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service,
    trace_id: genTraceId(),
    user_id: `usr_${Math.floor(Math.random() * 100000)}`,
    duration_ms: genDuration(2, 800),
    message: msg,
    host: `${service}-pod-${Math.floor(Math.random() * 5)}`,
    env: 'production'
  };

  if (userIdAsLabel) {
    entry._loki_label_user_id = entry.user_id;
  }

  return JSON.stringify(entry);
}

function getLogFile(service, isCardinality) {
  const filename = isCardinality ? `cardinality_${service}.log` : `${service}.log`;
  return path.join(LOG_DIR, filename);
}

if (!fs.existsSync(LOG_DIR)) {
  fs.mkdirSync(LOG_DIR, { recursive: true });
}

config.services.forEach(svc => {
  const f = getLogFile(svc, false);
  if (!fs.existsSync(f)) fs.writeFileSync(f, '');
  if (config.cardinality_test.enabled) {
    const cf = getLogFile(svc, true);
    if (!fs.existsSync(cf)) fs.writeFileSync(cf, '');
  }
});

console.log(JSON.stringify({
  timestamp: new Date().toISOString(),
  level: 'info',
  service: 'load-generator',
  message: `Starting log generation: ${config.log_rate_per_second} logs/sec across ${config.services.length} services`,
  cardinality_test: config.cardinality_test.add_user_id_as_label ? 'ENABLED' : 'SAFE'
}));

setInterval(() => {
  config.services.forEach(service => {
    const rand = Math.random() * 100;
    const level = rand < config.error_rate_percent ? 'error'
      : rand < config.error_rate_percent + 15 ? 'warn'
      : 'info';

    const line = buildLogLine(service, level, false) + '\n';
    fs.appendFileSync(getLogFile(service, false), line);

    if (config.cardinality_test.enabled) {
      const cardLine = buildLogLine(service, level, config.cardinality_test.add_user_id_as_label) + '\n';
      fs.appendFileSync(getLogFile(service, true), cardLine);
    }
  });
}, 1000 / config.log_rate_per_second * config.services.length);

setInterval(() => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'info',
    service: 'load-generator',
    message: 'Generation tick',
    logs_per_second: config.log_rate_per_second,
    services: config.services.length,
    uptime_seconds: Math.floor(process.uptime())
  }));
}, 10000);

process.on('SIGTERM', () => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'info',
    service: 'load-generator',
    message: 'Shutting down gracefully'
  }));
  process.exit(0);
});
