const { Pool } = require('pg');
const logger = require('./utils/logger');
require('dotenv').config();

function getSslConfig() {
  if (process.env.DATABASE_SSL === 'false') return false;

  const rejectUnauthorized = process.env.DATABASE_SSL_REJECT_UNAUTHORIZED !== 'false';
  const ssl = { rejectUnauthorized };

  if (process.env.DATABASE_SSL_CA) {
    ssl.ca = process.env.DATABASE_SSL_CA.replace(/\\n/g, '\n');
  }

  return ssl;
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: getSslConfig(),
});

async function initDB() {
  await pool.query('SELECT 1');
  logger.info('database_connection_ready');
}

module.exports = { pool, initDB, getSslConfig };
