const express = require('express');
const authMiddleware = require('../middleware/auth');
const { DEFAULT_LIMITS, getLimit, getUsage } = require('../utils/usage');
const { sendError } = require('../utils/errors');

const router = express.Router();
router.use(authMiddleware);

router.get('/', async (req, res) => {
  try {
    const usage = await Promise.all(
      Object.keys(DEFAULT_LIMITS).map(async (kind) => {
        const used = await getUsage(req.userId, kind);
        const limit = getLimit(kind);
        return {
          kind,
          used,
          limit,
          remaining: Math.max(0, limit - used),
          percent: limit > 0 ? Number(Math.min(1, used / limit).toFixed(3)) : 1,
        };
      })
    );

    res.json({ window: '24h', usage });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to load usage', err);
  }
});

module.exports = router;
