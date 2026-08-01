#!/usr/bin/env node
/**
 * Script to promote a user to admin role
 * Usage: node scripts/make-admin.js <username>
 */

require('dotenv').config();
const { pool } = require('../src/db');

async function makeAdmin(username) {
  if (!username) {
    console.error('Usage: node scripts/make-admin.js <username>');
    process.exit(1);
  }

  try {
    // Find user
    const userResult = await pool.query(
      'SELECT id, username, role FROM users WHERE username = $1',
      [username]
    );

    if (userResult.rows.length === 0) {
      console.error(`❌ User not found: ${username}`);
      console.log('\nAvailable users:');
      const allUsers = await pool.query('SELECT username FROM users ORDER BY created_at DESC LIMIT 10');
      allUsers.rows.forEach(u => console.log(`  - ${u.username}`));
      process.exit(1);
    }

    const user = userResult.rows[0];

    if (user.role === 'admin') {
      console.log(`✅ User ${username} is already an admin`);
      process.exit(0);
    }

    // Promote to admin
    await pool.query(
      'UPDATE users SET role = $1 WHERE id = $2',
      ['admin', user.id]
    );

    console.log(`✅ Successfully promoted ${username} to admin!`);
    console.log(`   User ID: ${user.id}`);
    console.log(`   Old role: ${user.role}`);
    console.log(`   New role: admin`);
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

const username = process.argv[2];
makeAdmin(username);
