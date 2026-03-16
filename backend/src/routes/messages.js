const express = require('express');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');

const router = express.Router();
router.use(authMiddleware);

const getSystemPrompt = (model) => {
  // Minimal context — let each model keep its native personality
  const base = 'Jawab dalam Bahasa Indonesia kecuali user meminta bahasa lain. Gunakan format markdown jika diperlukan. Jika user melampirkan file (gambar, PDF, kode, dll), isi file tersebut sudah diekstrak dan disertakan langsung di dalam pesan user. Kamu BISA membaca dan menganalisis konten file tersebut.';

  if (model && model.includes('image')) {
    return base + ' Kamu memiliki kemampuan menghasilkan gambar. Jika user meminta gambar, langsung generate gambar sesuai permintaan tanpa menolak.';
  }
  return base + ' Jika user meminta gambar, sarankan untuk mengganti ke model yang mendukung image generation seperti gemini-3-pro-image-preview.';
};

// Get messages for a chat
router.get('/:chatId/messages', async (req, res) => {
  try {
    // Verify chat belongs to user
    const chat = await pool.query(
      'SELECT id FROM chats WHERE id = $1 AND user_id = $2',
      [req.params.chatId, req.userId]
    );
    if (chat.rows.length === 0) {
      return res.status(404).json({ error: 'Chat not found' });
    }

    const result = await pool.query(
      `SELECT id, role, content, file_url, file_name, created_at
       FROM messages WHERE chat_id = $1
       ORDER BY created_at ASC`,
      [req.params.chatId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Get messages error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// Send message + get AI response
router.post('/:chatId/messages', async (req, res) => {
  const { content, file_url, file_name } = req.body;

  if (!content || !content.trim()) {
    return res.status(400).json({ error: 'Content required' });
  }

  try {
    // Verify chat belongs to user
    const chat = await pool.query(
      'SELECT id, model FROM chats WHERE id = $1 AND user_id = $2',
      [req.params.chatId, req.userId]
    );
    if (chat.rows.length === 0) {
      return res.status(404).json({ error: 'Chat not found' });
    }

    const model = chat.rows[0].model;

    // Save user message
    await pool.query(
      `INSERT INTO messages (chat_id, role, content, file_url, file_name)
       VALUES ($1, 'user', $2, $3, $4)`,
      [req.params.chatId, content, file_url || null, file_name || null]
    );

    // Get all messages for context
    const history = await pool.query(
      `SELECT role, content FROM messages
       WHERE chat_id = $1 ORDER BY created_at ASC`,
      [req.params.chatId]
    );

    // Build messages array with system prompt
    const allMessages = history.rows.map((m) => ({ role: m.role, content: m.content }));

    // Helper: get S3 client
    const getS3 = () => {
      const { S3Client } = require('@aws-sdk/client-s3');
      return new S3Client({
        region: 'auto',
        endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
        credentials: {
          accessKeyId: process.env.R2_ACCESS_KEY_ID,
          secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
        },
      });
    };

    // Helper: read file from R2 as buffer
    const readFileFromR2 = async (key) => {
      const { GetObjectCommand } = require('@aws-sdk/client-s3');
      const obj = await getS3().send(new GetObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME,
        Key: key,
      }));
      const chunks = [];
      for await (const chunk of obj.Body) chunks.push(chunk);
      return Buffer.concat(chunks);
    };

    // If the latest message has a file, process it for the AI
    let useMultimodal = false;
    console.log('[FILE] file_url:', file_url, 'file_name:', file_name);
    if (file_url && file_name) {
      const ext = file_name.split('.').pop()?.toLowerCase() || '';
      const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
      const textExts = [
        'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'swift',
        'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'rb', 'php',
        'html', 'css', 'scss', 'sass', 'less',
        'json', 'yaml', 'yml', 'xml', 'toml', 'ini', 'env',
        'sql', 'sh', 'bash', 'bat', 'ps1', 'cmd',
        'md', 'txt', 'log', 'csv',
        'vue', 'svelte', 'astro',
        'r', 'lua', 'perl', 'scala', 'clj', 'ex', 'exs', 'erl',
      ];

      try {
        if (imageExts.includes(ext)) {
          // Images → base64 multimodal content
          const buffer = await readFileFromR2(file_url);
          const base64 = buffer.toString('base64');
          const mimeMap = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', bmp: 'image/bmp' };
          const mime = mimeMap[ext] || 'image/png';

          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            // Convert to multimodal content format
            lastMsg.content = [
              { type: 'text', text: lastMsg.content },
              { type: 'image_url', image_url: { url: `data:${mime};base64,${base64}` } },
            ];
            useMultimodal = true;
          }
        } else if (ext === 'pdf') {
          // PDF → extract text with pdf-parse
          console.log('[PDF] Reading from R2:', file_url);
          const buffer = await readFileFromR2(file_url);
          console.log('[PDF] Buffer size:', buffer.length);
          const pdfParse = require('pdf-parse');
          const pdfData = await pdfParse(buffer);
          const pdfText = pdfData.text?.substring(0, 15000) || '[PDF kosong]';
          console.log('[PDF] Extracted', pdfText.length, 'chars from', pdfData.numpages, 'pages');

          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            lastMsg.content += `\n\n--- Isi dokumen PDF: ${file_name} (${pdfData.numpages} halaman) ---\n${pdfText}\n--- Akhir dokumen ---`;
            console.log('[PDF] Content appended to user message');
          }
        } else if (textExts.includes(ext)) {
          // Code/text → read content
          const buffer = await readFileFromR2(file_url);
          const fileContent = buffer.toString('utf-8').substring(0, 15000);

          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            lastMsg.content += `\n\n--- File: ${file_name} ---\n${fileContent}\n--- End of file ---`;
          }
        } else {
          // PPT/other → mention filename
          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            lastMsg.content += `\n\n[User melampirkan dokumen: ${file_name}. Analisis berdasarkan konteks percakapan.]`;
          }
        }
      } catch (fileErr) {
        console.error('[FILE ERROR]', fileErr.message, fileErr.stack);
        const lastMsg = allMessages[allMessages.length - 1];
        if (lastMsg && lastMsg.role === 'user') {
          lastMsg.content += `\n\n[File terlampir: ${file_name} - Error: ${fileErr.message}]`;
        }
      }
    }

    const messages = [
      { role: 'system', content: getSystemPrompt(model) },
      ...allMessages,
    ];

    // Call AI API
    const aiResponse = await fetch(`${process.env.AI_BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.AI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ model, messages, stream: false }),
    });

    if (!aiResponse.ok) {
      const errData = await aiResponse.json().catch(() => ({}));
      throw new Error(errData.error?.message || 'AI API error');
    }

    const aiData = await aiResponse.json();
    const aiMsg = aiData.choices?.[0]?.message;
    let aiContent = aiMsg?.content || '';

    // Handle image generation: router returns images in message.images[]
    const images = aiMsg?.images;
    if (images && Array.isArray(images) && images.length > 0) {
      const { PutObjectCommand } = require('@aws-sdk/client-s3');
      const { v4: uuidv4 } = require('uuid');
      const contentParts = [];

      if (aiContent) contentParts.push(aiContent);

      for (const img of images) {
        const dataUrl = img.image_url?.url || img.url || '';
        if (!dataUrl.startsWith('data:')) continue;

        // Parse data URI: data:image/jpeg;base64,/9j/4AAQ...
        const match = dataUrl.match(/^data:(image\/\w+);base64,(.+)$/s);
        if (!match) continue;

        const mimeType = match[1];
        const base64Data = match[2];
        const ext = mimeType.split('/')[1] || 'png';
        const key = `generated/${req.userId}/${uuidv4()}.${ext}`;

        try {
          const buffer = Buffer.from(base64Data, 'base64');
          await getS3().send(new PutObjectCommand({
            Bucket: process.env.R2_BUCKET_NAME,
            Key: key,
            Body: buffer,
            ContentType: mimeType,
          }));
          const baseUrl = `${req.protocol}://${req.get('host')}`;
          contentParts.push(`![Generated Image](${baseUrl}/api/files/${key})`);
        } catch (uploadErr) {
          console.error('Image upload to R2 error:', uploadErr);
          contentParts.push('[Gambar berhasil dibuat tapi gagal disimpan]');
        }
      }

      aiContent = contentParts.length > 0
        ? contentParts.join('\n\n')
        : 'Gambar berhasil dibuat tetapi tidak dapat ditampilkan.';
    }

    // Fallback if still empty
    if (!aiContent) aiContent = 'Maaf, tidak ada respons.';

    // Save AI response
    const saved = await pool.query(
      `INSERT INTO messages (chat_id, role, content)
       VALUES ($1, 'assistant', $2) RETURNING *`,
      [req.params.chatId, aiContent]
    );

    // Auto-generate title from first message
    const msgCount = history.rows.length;
    if (msgCount <= 1) {
      // First message — generate title
      try {
        const titleResponse = await fetch(
          `${process.env.AI_BASE_URL}/chat/completions`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${process.env.AI_API_KEY}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              model: 'gemini-2.5-flash-lite',
              messages: [
                {
                  role: 'user',
                  content: `Buatkan judul singkat (maksimal 5 kata, tanpa tanda kutip) untuk percakapan yang dimulai dengan pesan ini: "${content}"`,
                },
              ],
              stream: false,
            }),
          }
        );
        if (titleResponse.ok) {
          const titleData = await titleResponse.json();
          const title =
            titleData.choices?.[0]?.message?.content?.trim().slice(0, 100) ||
            content.slice(0, 50);
          await pool.query(
            'UPDATE chats SET title = $1, updated_at = NOW() WHERE id = $2',
            [title, req.params.chatId]
          );
        }
      } catch {
        // Title generation is best-effort, don't fail the request
        await pool.query(
          'UPDATE chats SET title = $1, updated_at = NOW() WHERE id = $2',
          [content.slice(0, 50), req.params.chatId]
        );
      }
    } else {
      // Update timestamp
      await pool.query(
        'UPDATE chats SET updated_at = NOW() WHERE id = $1',
        [req.params.chatId]
      );
    }

    res.json({
      message: saved.rows[0],
      chat_title_updated: msgCount <= 1,
    });
  } catch (err) {
    console.error('Send message error:', err);
    res.status(500).json({ error: err.message || 'Server error' });
  }
});

module.exports = router;
