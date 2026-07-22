const jwt = require('jsonwebtoken');
const { pool } = require('../db');

async function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'No token provided',
      code: 'UNAUTHORIZED',
      request_id: req.requestId,
    });
  }

  const token = header.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    // Transitional support: tokens issued before session tracking remain valid
    // until their JWT expiry. New tokens include sessionId and can be revoked.
    if (!decoded.sessionId) {
      req.userId = decoded.userId;
      req.username = decoded.username;
      req.sessionId = null;
      req.role = decoded.role || 'user';
      return next();
    }

    const session = await pool.query(
      `SELECT id FROM sessions
       WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > NOW()`,
      [decoded.sessionId, decoded.userId]
    );

    if (session.rows.length === 0) {
      return res.status(401).json({
        error: 'Invalid or expired token',
        code: 'SESSION_REVOKED',
        request_id: req.requestId,
      });
    }

    req.userId = decoded.userId;
    req.username = decoded.username;
    req.sessionId = decoded.sessionId;
    req.role = decoded.role || 'user';
    next();
  } catch {
    return res.status(401).json({
      error: 'Invalid or expired token',
      code: 'UNAUTHORIZED',
      request_id: req.requestId,
    });
  }
}

module.exports = authMiddleware;
