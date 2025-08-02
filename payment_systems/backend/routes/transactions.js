const express = require('express');
const router = express.Router();
const db = require('../database/db');

// Get all transactions for a user
router.get('/user/:userId', (req, res) => {
  const { userId } = req.params;
  const { limit = 50, offset = 0 } = req.query;

  db.all(
    `SELECT t.*, pm.type as payment_method_type, pm.last_four, pm.brand
     FROM transactions t
     LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE t.user_id = ?
     ORDER BY t.created_at DESC
     LIMIT ? OFFSET ?`,
    [userId, limit, offset],
    (err, rows) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      res.json(rows);
    }
  );
});

// Get transaction by ID
router.get('/:transactionId', (req, res) => {
  const { transactionId } = req.params;

  db.get(
    `SELECT t.*, pm.type as payment_method_type, pm.last_four, pm.brand, u.name as user_name
     FROM transactions t
     LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     LEFT JOIN users u ON t.user_id = u.id
     WHERE t.id = ?`,
    [transactionId],
    (err, row) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }

      if (!row) {
        return res.status(404).json({ error: 'Transaction not found' });
      }

      res.json(row);
    }
  );
});

// Get transaction statistics
router.get('/stats/:userId', (req, res) => {
  const { userId } = req.params;

  db.get(
    `SELECT 
       COUNT(*) as total_transactions,
       SUM(CASE WHEN status = 'succeeded' THEN amount ELSE 0 END) as total_amount,
       AVG(CASE WHEN status = 'succeeded' THEN amount ELSE NULL END) as avg_amount,
       COUNT(CASE WHEN status = 'succeeded' THEN 1 END) as successful_transactions,
       COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_transactions
     FROM transactions 
     WHERE user_id = ?`,
    [userId],
    (err, stats) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }

      res.json({
        ...stats,
        success_rate: stats.total_transactions > 0 
          ? (stats.successful_transactions / stats.total_transactions * 100).toFixed(2)
          : 0
      });
    }
  );
});

// Get recent transactions
router.get('/recent/:userId', (req, res) => {
  const { userId } = req.params;
  const { limit = 10 } = req.query;

  db.all(
    `SELECT t.*, pm.type as payment_method_type, pm.last_four, pm.brand
     FROM transactions t
     LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE t.user_id = ?
     ORDER BY t.created_at DESC
     LIMIT ?`,
    [userId, limit],
    (err, rows) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      res.json(rows);
    }
  );
});

// Update transaction status
router.patch('/:transactionId/status', (req, res) => {
  const { transactionId } = req.params;
  const { status } = req.body;

  if (!['pending', 'succeeded', 'failed', 'cancelled'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }

  const stmt = db.prepare('UPDATE transactions SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?');
  
  stmt.run(status, transactionId, function(err) {
    if (err) {
      console.error('Database error:', err);
      return res.status(500).json({ error: 'Failed to update transaction' });
    }

    if (this.changes === 0) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json({ success: true, message: 'Transaction status updated' });
  });

  stmt.finalize();
});

// Get transactions by date range
router.get('/user/:userId/date-range', (req, res) => {
  const { userId } = req.params;
  const { startDate, endDate } = req.query;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: 'Start date and end date are required' });
  }

  db.all(
    `SELECT t.*, pm.type as payment_method_type, pm.last_four, pm.brand
     FROM transactions t
     LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE t.user_id = ? AND DATE(t.created_at) BETWEEN ? AND ?
     ORDER BY t.created_at DESC`,
    [userId, startDate, endDate],
    (err, rows) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      res.json(rows);
    }
  );
});

// Get transactions by status
router.get('/user/:userId/status/:status', (req, res) => {
  const { userId, status } = req.params;

  db.all(
    `SELECT t.*, pm.type as payment_method_type, pm.last_four, pm.brand
     FROM transactions t
     LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE t.user_id = ? AND t.status = ?
     ORDER BY t.created_at DESC`,
    [userId, status],
    (err, rows) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      res.json(rows);
    }
  );
});

module.exports = router; 