const express = require('express');
const cors = require('cors');
const { initDB, pool } = require('./db');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chats');
const messageRoutes = require('./routes/messages');
const uploadRoutes = require('./routes/upload');
const fileRoutes = require('./routes/files');
const browseRoutes = require('./routes/browse');
const modelRoutes = require('./routes/models');
const usageRoutes = require('./routes/usage');
const authMiddleware = require('./middleware/auth');

const rateLimit = require('express-rate-limit');
const logger = require('./utils/logger');
const metrics = require('./utils/metrics');
const { runMigrations } = require('./migrations');
const {
  requestIdMiddleware,
  sendError,
  notFoundHandler,
  errorHandler,
} = require('./utils/errors');

const app = express();
const PORT = process.env.PORT || 4001;
const HOST = process.env.HOST || '127.0.0.1';
const isProduction = process.env.NODE_ENV === 'production';

const REQUIRED_ENV = [
  'DATABASE_URL',
  'JWT_SECRET',
  'AI_BASE_URL',
  'AI_API_KEY',
  'R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET_NAME',
];

const allowedOrigins = new Set(['https://askcore.dev', 'https://www.askcore.dev']);

if (!isProduction) {
  allowedOrigins.add('http://localhost:3000');
  allowedOrigins.add('http://localhost:4001');
  allowedOrigins.add('http://127.0.0.1:4001');
}

function getMissingEnv() {
  return REQUIRED_ENV.filter((name) => !process.env[name]);
}

async function checkReadiness() {
  const missingEnv = getMissingEnv();
  if (missingEnv.length > 0) {
    return { ready: false, missingEnv };
  }

  await pool.query('SELECT 1');
  return { ready: true, missingEnv: [] };
}

// Nginx is the only public reverse proxy in production.
app.disable('x-powered-by');
app.set('trust proxy', 1);

app.use(requestIdMiddleware);
app.use(logger.requestLogger);

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowedOrigins.has(origin)) {
        return callback(null, true);
      }
      return callback(null, false);
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    credentials: false,
  })
);
app.use(express.json({ limit: '10mb' }));

// Health checks are intentionally outside application rate limits.
app.get('/api/health', (_, res) => res.json({ status: 'ok' }));
app.get('/api/health/live', (_, res) => res.json({ status: 'ok' }));
app.get('/api/health/ready', async (req, res) => {
  try {
    const readiness = await checkReadiness();
    if (!readiness.ready) {
      return res.status(503).json({
        error: 'Readiness check failed',
        code: 'READINESS_FAILED',
        missing_env: readiness.missingEnv,
        request_id: req.requestId,
      });
    }

    return res.json({
      status: 'ok',
      checks: {
        config: 'ok',
        database: 'ok',
      },
      db_pool: {
        total: pool.totalCount,
        idle: pool.idleCount,
        waiting: pool.waitingCount,
      },
    });
  } catch (err) {
    return sendError(res, req, 503, 'Readiness check failed', err);
  }
});

app.get('/api/metrics', authMiddleware, (req, res) => {
  if (req.role !== 'admin' && req.role !== 'internal') {
    return sendError(res, req, 403, 'Admin access required', null, 'ADMIN_REQUIRED');
  }

  return res.json({
    request_id: req.requestId,
    metrics: metrics.snapshot(),
    db_pool: {
      total: pool.totalCount,
      idle: pool.idleCount,
      waiting: pool.waitingCount,
    },
  });
});

// Rate limiting
const globalLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: (req) => ({
    error: 'Too many requests, please try again later.',
    code: 'RATE_LIMITED',
    request_id: req.requestId,
  }),
});
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: (req) => ({
    error: 'Too many auth attempts, please try again later.',
    code: 'RATE_LIMITED',
    request_id: req.requestId,
  }),
});
const aiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: (req) => ({
    error: 'Too many AI requests, please slow down.',
    code: 'RATE_LIMITED',
    request_id: req.requestId,
  }),
});
app.use(globalLimiter);

// Routes
app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/chats', aiLimiter, messageRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/files', fileRoutes);
app.use('/api/browse', browseRoutes);
app.use('/api/models', modelRoutes);
app.use('/api/usage', usageRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

async function start() {
  if (process.env.RUN_MIGRATIONS_ON_START === 'true') {
    await runMigrations();
  }
  await initDB();
  const server = app.listen(PORT, HOST, () => {
    logger.info('server_started', { host: HOST, port: PORT });
  });
  return server;
}

if (require.main === module) {
  start().catch((err) => {
    logger.error('server_start_failed', { error: err.message || String(err), stack: err.stack });
    process.exit(1);
  });
}

module.exports = { app, start, checkReadiness, getMissingEnv };
