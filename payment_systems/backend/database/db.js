const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, 'payment_systems.db');
const db = new sqlite3.Database(dbPath);

// Initialize database tables
const initDatabase = () => {
  return new Promise((resolve, reject) => {
    db.serialize(() => {
      // Users table
      db.run(`
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT UNIQUE NOT NULL,
          password_hash TEXT NOT NULL,
          name TEXT NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Payment methods table
      db.run(`
        CREATE TABLE IF NOT EXISTS payment_methods (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          last_four TEXT,
          brand TEXT,
          is_default BOOLEAN DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users (id)
        )
      `);

      // Transactions table
      db.run(`
        CREATE TABLE IF NOT EXISTS transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          payment_method_id INTEGER,
          amount DECIMAL(10,2) NOT NULL,
          currency TEXT DEFAULT 'USD',
          status TEXT NOT NULL,
          payment_intent_id TEXT,
          description TEXT,
          metadata TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users (id),
          FOREIGN KEY (payment_method_id) REFERENCES payment_methods (id)
        )
      `);

      // Insert sample data
      db.run(`
        INSERT OR IGNORE INTO users (email, password_hash, name) 
        VALUES ('demo@example.com', '$2a$10$demo.hash.for.testing', 'Demo User')
      `);

      db.run(`
        INSERT OR IGNORE INTO payment_methods (user_id, type, last_four, brand, is_default) 
        VALUES (1, 'card', '4242', 'visa', 1)
      `);

      console.log('✅ Database initialized successfully');
      resolve();
    });
  });
};

// Initialize database on module load
initDatabase().catch(console.error);

module.exports = db; 