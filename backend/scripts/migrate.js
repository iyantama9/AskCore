#!/usr/bin/env node

require('dotenv').config();
const { pool } = require('../src/db');
const { runMigrations } = require('../src/migrations');

runMigrations()
  .then(async () => {
    console.log('Migrations complete');
    await pool.end();
  })
  .catch(async (err) => {
    console.error('Migration failed:', err);
    await pool.end().catch(() => {});
    process.exit(1);
  });
