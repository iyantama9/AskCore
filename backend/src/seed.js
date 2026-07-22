const bcrypt = require('bcryptjs');
const { pool, initDB } = require('./db');
require('dotenv').config();

const users = [
  { username: 'erza', password: 'Getcore1' },
  { username: 'fikri', password: 'Getcore1' },
  { username: 'nopek', password: 'Getcore1' },
  { username: 'ikmal', password: 'Getcore1' },
  { username: 'iyan', password: 'Getcore1' },
];

async function seed() {
  if (process.env.ALLOW_INSECURE_SEED !== 'true') {
    console.error(
      'Refusing to seed default users. Set ALLOW_INSECURE_SEED=true only in local/dev environments.'
    );
    process.exit(1);
  }

  await initDB();

  for (const user of users) {
    const hash = await bcrypt.hash(user.password, 10);
    await pool.query(
      `INSERT INTO users (username, password_hash)
       VALUES ($1, $2)
       ON CONFLICT (username) DO NOTHING`,
      [user.username, hash]
    );
    console.log(`  → User "${user.username}" seeded`);
  }

  console.log('✅ All users seeded');
  process.exit(0);
}

seed().catch((err) => {
  console.error('❌ Seed failed:', err);
  process.exit(1);
});
