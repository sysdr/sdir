const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

class Database {
  constructor() {
    this.dbPath = path.join(__dirname, 'database', 'postmortem.db');
    this.ensureDatabaseDir();
    this.db = new sqlite3.Database(this.dbPath);
    this.init();
  }

  ensureDatabaseDir() {
    const dir = path.dirname(this.dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  init() {
    this.db.serialize(() => {
      // Incidents table
      this.db.run(`
        CREATE TABLE IF NOT EXISTS incidents (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          severity TEXT NOT NULL,
          status TEXT NOT NULL,
          detected_at TEXT NOT NULL,
          resolved_at TEXT,
          affected_services TEXT,
          reporter TEXT NOT NULL,
          resolver TEXT,
          customer_impact TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Post-mortems table
      this.db.run(`
        CREATE TABLE IF NOT EXISTS postmortems (
          id TEXT PRIMARY KEY,
          incident_id TEXT NOT NULL,
          title TEXT NOT NULL,
          summary TEXT,
          timeline TEXT,
          root_cause TEXT,
          contributing_factors TEXT,
          lessons_learned TEXT,
          status TEXT DEFAULT 'draft',
          author TEXT NOT NULL,
          reviewers TEXT,
          approved_by TEXT,
          approved_at TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (incident_id) REFERENCES incidents(id)
        )
      `);

      // Action items table
      this.db.run(`
        CREATE TABLE IF NOT EXISTS action_items (
          id TEXT PRIMARY KEY,
          postmortem_id TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          priority TEXT NOT NULL,
          status TEXT DEFAULT 'open',
          assignee TEXT NOT NULL,
          due_date TEXT,
          completed_at TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (postmortem_id) REFERENCES postmortems(id)
        )
      `);

      // Timeline events table
      this.db.run(`
        CREATE TABLE IF NOT EXISTS timeline_events (
          id TEXT PRIMARY KEY,
          incident_id TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          event_type TEXT NOT NULL,
          description TEXT NOT NULL,
          actor TEXT,
          impact TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (incident_id) REFERENCES incidents(id)
        )
      `);

      // Knowledge base table
      this.db.run(`
        CREATE TABLE IF NOT EXISTS knowledge_base (
          id TEXT PRIMARY KEY,
          postmortem_id TEXT NOT NULL,
          tags TEXT,
          category TEXT,
          searchable_content TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (postmortem_id) REFERENCES postmortems(id)
        )
      `);

      // Insert sample data
      this.insertSampleData();
    });
  }

  insertSampleData() {
    const sampleIncident = {
      id: 'INC-2024-001',
      title: 'Database Connection Pool Exhaustion',
      description: 'High traffic caused database connection pool to reach maximum capacity',
      severity: 'high',
      status: 'resolved',
      detected_at: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      resolved_at: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000 + 4 * 60 * 60 * 1000).toISOString(),
      affected_services: JSON.stringify(['user-service', 'payment-service']),
      reporter: 'alice@company.com',
      resolver: 'bob@company.com',
      customer_impact: 'High - 15% of users unable to complete transactions'
    };

    this.db.get("SELECT id FROM incidents WHERE id = ?", [sampleIncident.id], (err, row) => {
      if (!row) {
        this.db.run(`
          INSERT INTO incidents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, Object.values(sampleIncident).concat([new Date().toISOString(), new Date().toISOString()]));
      }
    });
  }

  getDatabase() {
    return this.db;
  }
}

module.exports = Database;
