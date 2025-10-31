const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../db');
const { requireRole } = require('../middleware/auth');

// helper
async function q(sql, params) {
  const r = await db.query(sql, params);
  return r.rows || r[0] || r;
}
function genToken() {
  return crypto.randomBytes(32).toString('base64url');
}

// POST /api/invitations  (admin/operator_admin)
router.post('/', requireRole('admin','operator_admin'), async (req, res) => {
  const { role, operator_id = null, email, ttl_hours = 72 } = req.body || {};
  if (!role || !email) return res.status(400).json({ error: 'role și email obligatorii' });

  const token = genToken();
  await q(
    `INSERT INTO invitations (token, role, operator_id, email, expires_at, created_by)
     VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR), ?)`,
    [token, role, operator_id || null, email, ttl_hours, req.user?.id || null]
  );
  res.status(201).json({ token, expires_in_hours: ttl_hours });
});

// POST /api/invitations/accept  { token, name, password }
router.post('/accept', async (req, res) => {
  const { token, name, password } = req.body || {};
  if (!token || !name || !password) return res.status(400).json({ error: 'token, nume și parolă necesare' });

  const rows = await q('SELECT * FROM invitations WHERE token=? LIMIT 1', [token]);
  const inv = rows[0];
  if (!inv) return res.status(400).json({ error: 'invitație invalidă' });
  if (inv.used_at) return res.status(400).json({ error: 'invitație deja folosită' });
  if (new Date(inv.expires_at) < new Date()) return res.status(400).json({ error: 'invitație expirată' });

  const pass = await bcrypt.hash(password, 12);
  // creăm employee
  await q(
    `INSERT INTO employees (name, email, role, operator_id, active, password_hash)
     VALUES (?, ?, ?, ?, 1, ?)`,
    [name, inv.email, inv.role, inv.operator_id || 1, pass]
  );
  const emp = await q('SELECT id FROM employees WHERE email=? ORDER BY id DESC LIMIT 1', [inv.email]);

  // marcăm invitația ca folosită
  await q('UPDATE invitations SET used_at=NOW(), used_by=? WHERE id=?', [emp[0].id, inv.id]);

  res.json({ ok: true });
});

module.exports = router;
