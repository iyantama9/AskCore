const express = require('express');
const cors = require('cors');
const { initDB } = require('./db');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chats');
const messageRoutes = require('./routes/messages');
const uploadRoutes = require('./routes/upload');
const fileRoutes = require('./routes/files');

const app = express();
const PORT = process.env.PORT || 4000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/chats', messageRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/files', fileRoutes);

// Health check
app.get('/api/health', (_, res) => res.json({ status: 'ok' }));

// Start
async function start() {
  await initDB();
  app.listen(PORT, () => {
    console.log(`🚀 AskCore Backend running on http://localhost:${PORT}`);
  });
}

start().catch((err) => {
  console.error('❌ Failed to start:', err);
  process.exit(1);
});
