const { pool } = require('../db');
const metrics = require('./metrics');

const DEFAULT_LIMITS = {
  ai_request: 100,
  browse_request: 30,
  image_generation: 20,
  upload_count: 50,
  upload_bytes: 20 * 1024 * 1024,
};

const ENV_NAMES = {
  ai_request: 'QUOTA_AI_REQUESTS_PER_DAY',
  browse_request: 'QUOTA_BROWSE_REQUESTS_PER_DAY',
  image_generation: 'QUOTA_IMAGE_GENERATIONS_PER_DAY',
  upload_count: 'QUOTA_UPLOADS_PER_DAY',
  upload_bytes: 'QUOTA_UPLOAD_BYTES_PER_DAY',
};

function getLimit(kind) {
  const value = Number(process.env[ENV_NAMES[kind]] || DEFAULT_LIMITS[kind]);
  return Number.isFinite(value) && value >= 0 ? value : DEFAULT_LIMITS[kind];
}

async function getUsage(userId, kind) {
  const result = await pool.query(
    `SELECT COALESCE(SUM(amount), 0)::int AS total
     FROM usage_events
     WHERE user_id = $1 AND kind = $2 AND created_at > NOW() - INTERVAL '24 hours'`,
    [userId, kind]
  );
  return result.rows[0]?.total || 0;
}

async function checkQuota(userId, kind, amount = 1) {
  const limit = getLimit(kind);
  if (limit === 0) return { allowed: false, used: await getUsage(userId, kind), limit };

  const used = await getUsage(userId, kind);
  return {
    allowed: used + amount <= limit,
    used,
    limit,
    remaining: Math.max(0, limit - used),
  };
}

async function assertQuota(userId, kind, amount = 1) {
  const quota = await checkQuota(userId, kind, amount);
  if (!quota.allowed) {
    metrics.inc('quota_exceeded_total', { kind });
    const err = new Error(
      `Quota harian tercapai untuk ${kind}. Terpakai ${quota.used}/${quota.limit}. Coba lagi besok atau hubungi admin.`
    );
    err.statusCode = 429;
    err.code = 'QUOTA_EXCEEDED';
    err.quota = { kind, amount, used: quota.used, limit: quota.limit };
    throw err;
  }
  return quota;
}

async function recordUsage(userId, kind, amount = 1, metadata = {}) {
  await pool.query(
    `INSERT INTO usage_events (user_id, kind, amount, metadata)
     VALUES ($1, $2, $3, $4::jsonb)`,
    [userId, kind, amount, JSON.stringify(metadata)]
  );
}

module.exports = { DEFAULT_LIMITS, getLimit, getUsage, checkQuota, assertQuota, recordUsage };
