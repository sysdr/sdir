const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.PGHOST || 'postgres',
  port: 5432,
  database: process.env.PGDATABASE || 'migrationdb',
  user: process.env.PGUSER || 'postgres',
  password: process.env.PGPASSWORD || 'postgres',
});

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Broadcast to all WebSocket clients
function broadcast(data) {
  const msg = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(msg);
    }
  });
}

// ── GET: Dashboard state ──────────────────────────────────────
app.get('/api/state', async (req, res) => {
  try {
    const client = await pool.connect();

    // Current phase state
    const stateRes = await client.query(
      'SELECT key, value FROM migration_state'
    );
    const state = {};
    stateRes.rows.forEach(r => { state[r.key] = r.value; });

    // Schema column info
    const colRes = await client.query(`
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_name = 'users'
      ORDER BY ordinal_position
    `);

    // Migrations log
    const migRes = await client.query(
      'SELECT * FROM schema_migrations ORDER BY id DESC LIMIT 10'
    );

    // Recent lock events
    const lockRes = await client.query(
      'SELECT * FROM lock_events ORDER BY id DESC LIMIT 15'
    );

    // Row counts per column population
    let colCounts = { full_name: 0, first_name: 0, last_name: 0 };
    try {
      const fnRes = await client.query(
        `SELECT COUNT(*) FROM users WHERE full_name IS NOT NULL`
      );
      colCounts.full_name = parseInt(fnRes.rows[0].count);

      // Check if first_name column exists
      const fnColExists = colRes.rows.some(r => r.column_name === 'first_name');
      if (fnColExists) {
        const firstRes = await client.query(
          `SELECT COUNT(*) FROM users WHERE first_name IS NOT NULL`
        );
        colCounts.first_name = parseInt(firstRes.rows[0].count);
      }

      const lnColExists = colRes.rows.some(r => r.column_name === 'last_name');
      if (lnColExists) {
        const lastRes = await client.query(
          `SELECT COUNT(*) FROM users WHERE last_name IS NOT NULL`
        );
        colCounts.last_name = parseInt(lastRes.rows[0].count);
      }
    } catch (e) {
      // columns may not exist yet
    }

    // Sample rows
    const sampleRes = await client.query(
      `SELECT * FROM users ORDER BY id LIMIT 5`
    );

    client.release();
    res.json({
      state,
      columns: colRes.rows,
      migrations: migRes.rows,
      lockEvents: lockRes.rows,
      colCounts,
      sampleRows: sampleRes.rows,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Execute expand phase ────────────────────────────────
app.post('/api/migrate/expand', async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Record start
    const migId = await client.query(`
      INSERT INTO schema_migrations (phase, description, status)
      VALUES ('expand', 'ADD COLUMN first_name, last_name (nullable)', 'running')
      RETURNING id
    `);
    const id = migId.rows[0].id;

    const t0 = Date.now();

    // Phase 1: ADD COLUMN — metadata-only in PG 11+
    await client.query(`
      ALTER TABLE users
        ADD COLUMN IF NOT EXISTS first_name VARCHAR(127),
        ADD COLUMN IF NOT EXISTS last_name VARCHAR(127)
    `);

    const lockMs = Date.now() - t0;
    await client.query(
      `SELECT record_lock_event('ADD COLUMN (nullable)', $1, 'expand')`,
      [lockMs]
    );

    // Mark complete
    await client.query(`
      UPDATE schema_migrations
      SET completed_at = NOW(), status = 'completed', rows_processed = 0
      WHERE id = $1
    `, [id]);

    await client.query(`
      UPDATE migration_state SET value = 'expand', updated_at = NOW()
      WHERE key = 'current_phase'
    `);

    await client.query('COMMIT');
    client.release();

    broadcast({ type: 'phase_change', phase: 'expand', lockMs });
    res.json({ success: true, lockMs, message: 'Expand phase complete — columns added, no data written yet' });
  } catch (err) {
    await client.query('ROLLBACK');
    client.release();
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Run backfill ────────────────────────────────────────
app.post('/api/migrate/backfill', async (req, res) => {
  const batchSize = parseInt(req.body.batchSize) || 5000;
  const sleepMs = parseInt(req.body.sleepMs) || 100;

  try {
    const migRes = await pool.query(`
      INSERT INTO schema_migrations (phase, description, status)
      VALUES ('backfill', $1, 'running')
      RETURNING id
    `, [`Backfill first_name/last_name from full_name — batch=${batchSize}`]);
    const migId = migRes.rows[0].id;

    // Run backfill asynchronously
    (async () => {
      let offset = 0;
      let totalProcessed = 0;
      const totalRes = await pool.query(
        `SELECT COUNT(*) FROM users WHERE first_name IS NULL`
      );
      const total = parseInt(totalRes.rows[0].count);

      while (true) {
        const batchRes = await pool.query(`
          UPDATE users
          SET
            first_name = split_part(full_name, ' ', 1),
            last_name = CASE
              WHEN strpos(full_name, ' ') > 0
              THEN substring(full_name FROM strpos(full_name, ' ') + 1)
              ELSE ''
            END
          WHERE id IN (
            SELECT id FROM users
            WHERE first_name IS NULL
            LIMIT $1
          )
        `, [batchSize]);

        const updated = batchRes.rowCount;
        totalProcessed += updated;
        const progress = total > 0 ? Math.round((totalProcessed / total) * 100) : 100;

        await pool.query(`
          UPDATE migration_state SET value = $1, updated_at = NOW()
          WHERE key = 'backfill_progress'
        `, [progress.toString()]);

        broadcast({
          type: 'backfill_progress',
          processed: totalProcessed,
          total,
          progress,
          batchUpdated: updated,
        });

        if (updated === 0) break;

        await new Promise(r => setTimeout(r, sleepMs));
      }

      // Mark complete
      await pool.query(`
        UPDATE schema_migrations
        SET completed_at = NOW(), status = 'completed', rows_processed = $1
        WHERE id = $2
      `, [totalProcessed, migId]);

      await pool.query(`
        UPDATE migration_state SET value = 'backfill_complete', updated_at = NOW()
        WHERE key = 'current_phase'
      `);

      broadcast({ type: 'backfill_complete', totalProcessed });
    })().catch(err => console.error('Backfill error:', err));

    res.json({ success: true, message: 'Backfill started in background', batchSize, sleepMs });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Activate dual-write ─────────────────────────────────
app.post('/api/migrate/dual-write', async (req, res) => {
  try {
    await pool.query(`
      UPDATE migration_state SET value = 'true', updated_at = NOW()
      WHERE key = 'dual_write_active'
    `);
    await pool.query(`
      UPDATE migration_state SET value = 'dual_write', updated_at = NOW()
      WHERE key = 'current_phase'
    `);
    await pool.query(`
      INSERT INTO schema_migrations (phase, description, status, completed_at)
      VALUES ('dual_write', 'Application now writes to both old and new columns', 'completed', NOW())
    `);
    broadcast({ type: 'phase_change', phase: 'dual_write' });
    res.json({ success: true, message: 'Dual-write mode activated — all new writes go to both columns' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Simulate writes ──────────────────────────────────────
app.post('/api/simulate/write', async (req, res) => {
  try {
    const stateRes = await pool.query(
      `SELECT key, value FROM migration_state`
    );
    const state = {};
    stateRes.rows.forEach(r => { state[r.key] = r.value; });

    const dualWrite = state.dual_write_active === 'true';
    const phase = state.current_phase;
    const names = [
      ['Sophia','Lee'],['James','Chen'],['Mia','Patel'],['Liam','Kim'],['Emma','Nguyen']
    ];
    const [first, last] = names[Math.floor(Math.random() * names.length)];
    const ts = Date.now();

    if (dualWrite) {
      await pool.query(`
        INSERT INTO users (full_name, first_name, last_name, email)
        VALUES ($1, $2, $3, $4)
      `, [`${first} ${last}`, first, last, `sim${ts}@demo.com`]);
    } else {
      await pool.query(`
        INSERT INTO users (full_name, email)
        VALUES ($1, $2)
      `, [`${first} ${last}`, `sim${ts}@demo.com`]);
    }

    broadcast({ type: 'write', dualWrite, phase, name: `${first} ${last}` });
    res.json({ success: true, dualWrite, written: { first, last, full: `${first} ${last}` } });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Contract phase (drop column) ────────────────────────
app.post('/api/migrate/contract', async (req, res) => {
  const client = await pool.connect();
  try {
    // Verify backfill is 100%
    const nullCheck = await client.query(
      `SELECT COUNT(*) FROM users WHERE first_name IS NULL`
    );
    const nullCount = parseInt(nullCheck.rows[0].count);
    if (nullCount > 0) {
      client.release();
      return res.status(400).json({
        error: `Cannot contract: ${nullCount} rows still have NULL first_name. Complete backfill first.`
      });
    }

    await client.query('BEGIN');

    const migRes = await client.query(`
      INSERT INTO schema_migrations (phase, description, status)
      VALUES ('contract', 'DROP COLUMN full_name', 'running')
      RETURNING id
    `);
    const id = migRes.rows[0].id;

    const t0 = Date.now();
    await client.query(`ALTER TABLE users DROP COLUMN IF EXISTS full_name`);
    const lockMs = Date.now() - t0;

    await client.query(
      `SELECT record_lock_event('DROP COLUMN full_name', $1, 'contract')`,
      [lockMs]
    );

    await client.query(`
      UPDATE schema_migrations
      SET completed_at = NOW(), status = 'completed'
      WHERE id = $1
    `, [id]);

    await client.query(`
      UPDATE migration_state
      SET value = 'contract_complete', updated_at = NOW()
      WHERE key = 'current_phase'
    `);
    await client.query(`
      UPDATE migration_state
      SET value = 'true', updated_at = NOW()
      WHERE key = 'contract_complete'
    `);
    await client.query(`
      UPDATE migration_state
      SET value = 'false', updated_at = NOW()
      WHERE key = 'dual_write_active'
    `);

    await client.query('COMMIT');
    client.release();

    broadcast({ type: 'phase_change', phase: 'contract_complete', lockMs });
    res.json({ success: true, lockMs, message: `Contract complete. Lock held for ${lockMs}ms.` });
  } catch (err) {
    await client.query('ROLLBACK');
    client.release();
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Simulate naive migration (for comparison) ───────────
app.post('/api/simulate/naive', async (req, res) => {
  try {
    // Simulate the lock timing of a naive migration (no actual table rewrite, just timing sim)
    const simulatedLockMs = 2000 + Math.random() * 3000; // 2-5 seconds simulated
    await pool.query(
      `SELECT record_lock_event($1, $2, 'naive')`,
      ['NAIVE: ALTER TABLE (simulated full rewrite)', simulatedLockMs]
    );
    broadcast({ type: 'naive_migration', simulatedLockMs });
    res.json({
      success: true,
      simulatedLockMs,
      message: `Naive migration would have locked table for ~${Math.round(simulatedLockMs)}ms (simulated for 50K rows; scales to minutes at 200M rows)`
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST: Reset demo ──────────────────────────────────────────
app.post('/api/reset', async (req, res) => {
  try {
    // Re-add full_name if dropped, reset state
    const cols = await pool.query(`
      SELECT column_name FROM information_schema.columns WHERE table_name = 'users'
    `);
    const colNames = cols.rows.map(r => r.column_name);

    if (!colNames.includes('full_name')) {
      await pool.query(`ALTER TABLE users ADD COLUMN full_name VARCHAR(255)`);
      // Reconstruct from first/last
      await pool.query(`
        UPDATE users SET full_name = first_name || ' ' || last_name
      `);
    }
    if (colNames.includes('first_name')) {
      await pool.query(`ALTER TABLE users DROP COLUMN IF EXISTS first_name`);
    }
    if (colNames.includes('last_name')) {
      await pool.query(`ALTER TABLE users DROP COLUMN IF EXISTS last_name`);
    }

    await pool.query(`TRUNCATE schema_migrations, lock_events`);
    await pool.query(`
      UPDATE migration_state SET value = 'pre_migration', updated_at = NOW()
      WHERE key = 'current_phase'
    `);
    await pool.query(`
      UPDATE migration_state SET value = '0', updated_at = NOW()
      WHERE key = 'backfill_progress'
    `);
    await pool.query(`
      UPDATE migration_state SET value = 'false', updated_at = NOW()
      WHERE key IN ('dual_write_active', 'contract_complete')
    `);

    broadcast({ type: 'reset' });
    res.json({ success: true, message: 'Demo reset to initial state' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Health check
app.get('/health', (req, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => console.log(`Backend running on :${PORT}`));
