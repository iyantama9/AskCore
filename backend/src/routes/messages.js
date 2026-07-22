const express = require('express');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { validatePublicHttpUrl } = require('../utils/urlSafety');
const { assertCanReadR2Key, recordFile } = require('../utils/files');
const { sendError } = require('../utils/errors');
const { assertQuota, recordUsage } = require('../utils/usage');
const { assertValidModel } = require('../utils/modelCatalog');
const logger = require('../utils/logger');
const metrics = require('../utils/metrics');

const router = express.Router();
router.use(authMiddleware);

const TITLE_MODEL = 'qc/qwen-flash';

function toAnthropicContent(content) {
  if (!Array.isArray(content)) return content;

  return content.map((part) => {
    if (part.type === 'image_url') {
      const dataUrl = part.image_url?.url || '';
      const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/s);
      if (match) {
        return {
          type: 'image',
          source: { type: 'base64', media_type: match[1], data: match[2] },
        };
      }
    }
    return part;
  });
}

async function fetchAI({ model, messages, stream = false, max_tokens = 4096 }) {
  const started = process.hrtime.bigint();
  const streamLabel = stream ? 'true' : 'false';
  const system = messages
    .filter((message) => message.role === 'system')
    .map((message) => message.content)
    .filter(Boolean)
    .join('\n\n');

  const anthropicMessages = messages
    .filter((message) => message.role !== 'system')
    .map((message) => ({
      role: message.role,
      content: toAnthropicContent(message.content),
    }));

  const response = await fetch(`${process.env.AI_BASE_URL}/messages`, {
    method: 'POST',
    headers: {
      'x-api-key': process.env.AI_API_KEY,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      messages: anthropicMessages,
      ...(system ? { system } : {}),
      max_tokens,
      stream,
    }),
  });

  const durationMs = Number(process.hrtime.bigint() - started) / 1_000_000;
  metrics.observe('ai_latency_ms', durationMs, {
    model,
    stream: streamLabel,
    status: String(response.status),
  });
  if (!response.ok) {
    metrics.inc('ai_failures_total', {
      model,
      stream: streamLabel,
      status: String(response.status),
    });
  }

  if (stream) return response;

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = data.error?.message || data.error || data.detail || 'AI API error';
    return new Response(JSON.stringify({ error: { message } }), {
      status: response.status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const content = Array.isArray(data.content)
    ? data.content.filter((block) => block.type === 'text').map((block) => block.text).join('')
    : '';
  const images = Array.isArray(data.content)
    ? data.content
        .filter((block) => block.type === 'image')
        .map((block) => {
          if (block.source?.type === 'url') {
            return { image_url: { url: block.source.url } };
          }
          if (block.source?.type === 'base64') {
            return {
              image_url: {
                url: `data:${block.source.media_type};base64,${block.source.data}`,
              },
            };
          }
          return null;
        })
        .filter(Boolean)
    : [];

  return new Response(JSON.stringify({
    choices: [{
      message: {
        role: 'assistant',
        content,
        ...(images.length > 0 ? { images } : {}),
      },
      finish_reason: data.stop_reason || 'stop',
    }],
    usage: data.usage || {},
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// S3/R2 singleton client
const s3Client = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

// --- Browse helpers ---

// Direct HTTP search via DuckDuckGo Lite (no Puppeteer = no CAPTCHA)
async function executeSearch(query) {
  try {
    const url = `https://lite.duckduckgo.com/lite/?q=${encodeURIComponent(query)}`;
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Accept': 'text/html',
        'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
      },
    });
    const html = await resp.text();

    // Parse DuckDuckGo Lite HTML results
    // Links: <a rel="nofollow" href="//duckduckgo.com/l/?uddg=ENCODED_URL" class='result-link'>Title</a>
    // Snippets: <td class='result-snippet'>text</td>
    const results = [];

    // Extract result links with class='result-link'
    const linkRegex = /<a[^>]+class=['"]result-link['"][^>]*href=['"]([^'"]+)['"][^>]*>([^<]+)<\/a>|<a[^>]+href=['"]([^'"]+)['"][^>]*class=['"]result-link['"][^>]*>([^<]+)<\/a>/gi;
    let match;
    while ((match = linkRegex.exec(html)) !== null) {
      const rawHref = match[1] || match[3];
      const title = (match[2] || match[4] || '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#x27;/g, "'").replace(/&#39;/g, "'").trim();

      // Extract actual URL from DDG redirect: //duckduckgo.com/l/?uddg=ENCODED_URL
      let actualUrl = rawHref;
      const uddgMatch = rawHref.match(/[?&]uddg=([^&]+)/);
      if (uddgMatch) {
        actualUrl = decodeURIComponent(uddgMatch[1]);
      } else if (rawHref.startsWith('//')) {
        actualUrl = 'https:' + rawHref;
      }

      if (actualUrl.startsWith('http') && !actualUrl.includes('duckduckgo.com')) {
        results.push({ title, url: actualUrl, snippet: '' });
      }
    }

    // Extract snippets
    const snippetRegex = /<td[^>]*class=['"]result-snippet['"][^>]*>([\s\S]*?)<\/td>/gi;
    let snippetMatch;
    let idx = 0;
    while ((snippetMatch = snippetRegex.exec(html)) !== null && idx < results.length) {
      const snippet = snippetMatch[1]
        .replace(/<[^>]+>/g, '')
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&#x27;/g, "'")
        .replace(/&#39;/g, "'")
        .replace(/&nbsp;/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .substring(0, 300);
      results[idx].snippet = snippet;
      idx++;
    }

    const top = results.slice(0, 10);
    let text = `Hasil pencarian untuk "${query}":\n\n`;
    top.forEach((r, i) => {
      text += `${i + 1}. ${r.title}\n   URL: ${r.url}\n`;
      if (r.snippet) text += `   ${r.snippet}\n`;
      text += '\n';
    });

    if (top.length === 0) {
      text += '(Tidak ada hasil ditemukan)\n';
    }

    logger.info('browse_search_complete', { result_count: top.length });
    return { type: 'search', query, results: top, text, resultCount: top.length };
  } catch (err) {
    metrics.inc('browse_failures_total', { action: 'search' });
    logger.warn('browse_search_failed', { error: err.message });
    return { type: 'search', query, results: [], text: `Pencarian gagal: ${err.message}`, resultCount: 0 };
  }
}

function parseBrowseCommands(text) {
  const commands = [];
  if (!text) return commands;

  // [BROWSE:url]
  const browseMatches = text.matchAll(/\[BROWSE:([^\]]+)\]/gi);
  for (const m of browseMatches) {
    commands.push({ action: 'navigate', url: m[1].trim() });
  }

  // [SEARCH:query] → Uses direct HTTP fetch (no Puppeteer)
  const searchMatches = text.matchAll(/\[SEARCH:([^\]]+)\]/gi);
  for (const m of searchMatches) {
    commands.push({ action: 'search', query: m[1].trim() });
  }

  // [CLICK:selector]
  const clickMatches = text.matchAll(/\[CLICK:([^\]]+)\]/gi);
  for (const m of clickMatches) {
    commands.push({ action: 'click', selector: m[1].trim() });
  }

  // [TYPE:selector|text]
  const typeMatches = text.matchAll(/\[TYPE:([^|]+)\|([^\]]+)\]/gi);
  for (const m of typeMatches) {
    commands.push({ action: 'type', selector: m[1].trim(), text: m[2].trim() });
  }

  // [SCROLL:direction]
  const scrollMatches = text.matchAll(/\[SCROLL:(up|down)\]/gi);
  for (const m of scrollMatches) {
    commands.push({ action: 'scroll', scroll_direction: m[1].toLowerCase() });
  }

  // [ENTER]
  if (/\[ENTER\]/i.test(text)) {
    commands.push({ action: 'press_enter' });
  }

  return commands;
}

// Execute a single browse command using Puppeteer directly
let sharedBrowser = null;
let sharedIdleTimer = null;

async function getSharedBrowser() {
  if (sharedBrowser) {
    if (sharedIdleTimer) clearTimeout(sharedIdleTimer);
    sharedIdleTimer = setTimeout(async () => {
      try { await sharedBrowser.close(); } catch(_) {}
      sharedBrowser = null;
    }, 120000);
    return sharedBrowser;
  }

  const puppeteer = require('puppeteer-extra');
  const StealthPlugin = require('puppeteer-extra-plugin-stealth');
  puppeteer.use(StealthPlugin());

  sharedBrowser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage',
      '--disable-gpu', '--single-process', '--no-zygote',
    ],
    executablePath: process.env.CHROME_PATH || undefined,
  });

  logger.info('browse_browser_launched', { mode: 'stealth' });
  sharedIdleTimer = setTimeout(async () => {
    try { await sharedBrowser.close(); } catch(_) {}
    sharedBrowser = null;
  }, 120000);

  return sharedBrowser;
}

async function createIsolatedContext(browser) {
  if (typeof browser.createBrowserContext === 'function') {
    return browser.createBrowserContext();
  }
  if (typeof browser.createIncognitoBrowserContext === 'function') {
    return browser.createIncognitoBrowserContext();
  }
  return browser;
}

async function executeBrowseCommand(cmd, req) {
  const safeNavigateUrl = cmd.action === 'navigate' ? await validatePublicHttpUrl(cmd.url) : null;
  const browser = await getSharedBrowser();
  const context = await createIsolatedContext(browser);
  try {
    const page = await context.newPage();
    // Set realistic user agent to bypass bot detection
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36');
    await page.setViewport({ width: 1280, height: 800 });

    switch (cmd.action) {
      case 'navigate': {
        await page.goto(safeNavigateUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
        await new Promise(r => setTimeout(r, 1500));
        break;
      }
      case 'click':
        if (cmd.selector) {
          await page.click(cmd.selector).catch(() => {});
          await new Promise(r => setTimeout(r, 1000));
        }
        break;
      case 'type':
        if (cmd.selector && cmd.text) {
          await page.type(cmd.selector, cmd.text, { delay: 50 }).catch(() => {});
          await new Promise(r => setTimeout(r, 500));
        }
        break;
      case 'scroll':
        await page.evaluate((d) => window.scrollBy(0, d), cmd.scroll_direction === 'up' ? -500 : 500);
        await new Promise(r => setTimeout(r, 500));
        break;
      case 'press_enter':
        await page.keyboard.press('Enter');
        await new Promise(r => setTimeout(r, 2000));
        break;
    }

    // Screenshot
    const screenshotBuffer = await page.screenshot({ type: 'jpeg', quality: 60 });
    const key = `browse/${req.userId}/${Date.now()}.jpg`;
    await s3Client.send(new PutObjectCommand({
      Bucket: process.env.R2_BUCKET_NAME, Key: key, Body: screenshotBuffer, ContentType: 'image/jpeg',
    }));

    // Extract text
    const pageText = await page.evaluate(() => {
      const clone = document.body.cloneNode(true);
      clone.querySelectorAll('script, style, noscript, svg').forEach(el => el.remove());
      return (clone.innerText || '').substring(0, 3000);
    }).catch(() => '');

    // Extract elements
    const elements = await page.evaluate(() => {
      const items = [];
      document.querySelectorAll('a[href]').forEach((el, i) => {
        if (i < 10 && el.innerText?.trim()) items.push({ type: 'link', text: el.innerText.trim().substring(0, 80), href: el.href });
      });
      document.querySelectorAll('input, textarea').forEach((el, i) => {
        if (i < 5) items.push({ type: 'input', name: el.name || el.placeholder || el.type, selector: el.id ? `#${el.id}` : `input[name="${el.name}"]` });
      });
      return items;
    }).catch(() => []);

    return {
      screenshot_url: `${process.env.PUBLIC_BASE_URL || 'https://askcore.dev'}/api/files/${key}`,
      page_title: await page.title().catch(() => ''),
      current_url: page.url(),
      text_content: pageText,
      elements,
    };
  } finally {
    if (context && typeof context.close === 'function') {
      await context.close().catch(() => {});
    }
  }
}
// --- End browse helpers ---

const getSystemPrompt = (model, tools = []) => {
  let base = `Jawab dalam Bahasa Indonesia kecuali user meminta bahasa lain. Gunakan format markdown jika diperlukan. Jika user melampirkan file (gambar, PDF, kode, dll), isi file tersebut sudah diekstrak dan disertakan langsung di dalam pesan user. Kamu BISA membaca dan menganalisis konten file tersebut.

FORMAT MATEMATIKA:
- Tulis persamaan inline dengan delimiter LaTeX $...$.
- Tulis persamaan yang berdiri sendiri dengan delimiter LaTeX display pada baris terpisah: $$ lalu persamaan lalu $$.
- Gunakan sintaks LaTeX seperti \\frac, \\sqrt, \\sum, \\times, \\mod, subscript _, dan superscript ^.
- JANGAN bungkus rumus matematika dalam fenced code block atau backtick.
- Gunakan fenced code block hanya untuk kode program atau pseudocode.`;

  if (model && model.includes('image')) {
    base += ' Kamu memiliki kemampuan menghasilkan gambar. Jika user meminta gambar, langsung generate gambar sesuai permintaan tanpa menolak.';
  } else {
    base += ' Jika user meminta gambar, sarankan untuk mengganti ke model yang mendukung image generation seperti gemini-3-pro-image-preview.';
  }

  if (tools.includes('browse_web')) {
    base += `\n\nIMPORTANT: Kamu memiliki kemampuan BROWSE WEB yang AKTIF dan BERFUNGSI. Browser kamu sudah siap dan bisa digunakan langsung TANPA ERROR. Jangan pernah bilang kamu tidak bisa browsing atau ada error — browser PASTI berfungsi.

Ketika user meminta informasi dari internet, kamu WAJIB memulai jawaban dengan perintah browsing. JANGAN menjawab dari pengetahuan saja — SELALU cari dulu di internet.

Perintah yang tersedia:
- [SEARCH:query] — cari di Google (UTAMAKAN ini untuk mencari informasi)
- [BROWSE:url] — buka URL spesifik
- [CLICK:css_selector] — klik elemen
- [TYPE:css_selector|teks] — ketik teks di input field
- [SCROLL:down] atau [SCROLL:up] — scroll halaman
- [ENTER] — tekan Enter

ATURAN:
1. Jawaban pertama kamu HARUS dimulai dengan [SEARCH:...] atau [BROWSE:...]. Tidak boleh ada teks lain sebelum perintah browsing.
2. Setelah menerima hasil browsing, jawab pertanyaan user berdasarkan informasi dari web. Jangan keluarkan perintah browsing lagi kecuali perlu langkah tambahan.
3. Sertakan sumber URL di jawaban akhir.

Contoh jawaban pertama yang BENAR:
User: "carikan jurnal machine learning"
Kamu: [SEARCH:machine learning journal paper 2024]

Contoh yang SALAH:
User: "carikan jurnal machine learning"  
Kamu: "Maaf, saya tidak bisa browsing karena..." (INI DILARANG)`;
  }

  return base;
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
      return sendError(res, req, 404, 'Chat not found');
    }

    const result = await pool.query(
      `SELECT id, role, content, file_url, file_name, created_at
       FROM messages WHERE chat_id = $1
       ORDER BY created_at ASC`,
      [req.params.chatId]
    );
    res.json(result.rows);
  } catch (err) {
    return sendError(res, req, 500, 'Server error', err);
  }
});

// Edit message
router.put('/:chatId/messages/:messageId', async (req, res) => {
  const { content } = req.body;
  if (!content || !content.trim()) {
    return sendError(res, req, 400, 'Content required', null, 'CONTENT_REQUIRED');
  }
  try {
    const chat = await pool.query(
      'SELECT id FROM chats WHERE id = $1 AND user_id = $2',
      [req.params.chatId, req.userId]
    );
    if (chat.rows.length === 0) {
      return sendError(res, req, 404, 'Chat not found');
    }
    const result = await pool.query(
      `UPDATE messages SET content = $1 WHERE id = $2 AND chat_id = $3 AND role = 'user' RETURNING *`,
      [content.trim(), req.params.messageId, req.params.chatId]
    );
    if (result.rows.length === 0) {
      return sendError(res, req, 404, 'Message not found or not editable', null, 'MESSAGE_NOT_EDITABLE');
    }
    res.json(result.rows[0]);
  } catch (err) {
    return sendError(res, req, 500, 'Server error', err);
  }
});

// Send message + get AI response
router.post('/:chatId/messages', async (req, res) => {
  const { content, file_url, file_name, file_urls, file_names, tools } = req.body;

  if (!content || !content.trim()) {
    return sendError(res, req, 400, 'Content required', null, 'CONTENT_REQUIRED');
  }

  // Support both single and multi file (backward compat)
  const urls = file_urls || (file_url ? [file_url] : []);
  const names = file_names || (file_name ? [file_name] : []);

  try {
    // Verify chat belongs to user
    const chat = await pool.query(
      'SELECT id, model FROM chats WHERE id = $1 AND user_id = $2',
      [req.params.chatId, req.userId]
    );
    if (chat.rows.length === 0) {
      return sendError(res, req, 404, 'Chat not found');
    }

    const model = chat.rows[0].model;
    const modelInfo = assertValidModel(model);
    await assertQuota(req.userId, 'ai_request', 1);
    if (tools && tools.includes('browse_web')) {
      await assertQuota(req.userId, 'browse_request', 1);
    }
    if (modelInfo.supports_image_generation) {
      await assertQuota(req.userId, 'image_generation', 1);
    }

    // Save user message (store first file for backward compat in DB)
    await pool.query(
      `INSERT INTO messages (chat_id, role, content, file_url, file_name)
       VALUES ($1, 'user', $2, $3, $4)`,
      [req.params.chatId, content, urls[0] || null, names[0] || null]
    );

    // Get all messages for context
    const history = await pool.query(
      `SELECT role, content FROM messages
       WHERE chat_id = $1 ORDER BY created_at ASC`,
      [req.params.chatId]
    );

    // Build messages array with system prompt (cap at 30 messages for context window)
    const historyRows = history.rows;
    const cappedHistory = historyRows.length > 30 ? historyRows.slice(-30) : historyRows;
    const allMessages = cappedHistory.map((m) => ({ role: m.role, content: m.content }));

    // Helper: read file from R2 as buffer
    const readFileFromR2 = async (key) => {
      const safeKey = await assertCanReadR2Key(req.userId, key);
      const obj = await s3Client.send(new GetObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME,
        Key: safeKey,
      }));
      const chunks = [];
      for await (const chunk of obj.Body) chunks.push(chunk);
      return Buffer.concat(chunks);
    };

    // Process all attached files for the AI
    let useMultimodal = false;
    const imageParts = []; // Collect all image parts for multimodal

    for (let i = 0; i < urls.length; i++) {
      const fileUrl = urls[i];
      const fileName = names[i] || 'file';
      logger.info('message_attachment_received', {
        request_id: req.requestId,
        index: i + 1,
        total: urls.length,
        file_name: fileName,
      });

      if (!fileUrl || !fileName) continue;

      const ext = fileName.split('.').pop()?.toLowerCase() || '';
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
          const buffer = await readFileFromR2(fileUrl);
          const base64 = buffer.toString('base64');
          const mimeMap = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', bmp: 'image/bmp' };
          const mime = mimeMap[ext] || 'image/png';
          imageParts.push({ type: 'image_url', image_url: { url: `data:${mime};base64,${base64}` } });
          useMultimodal = true;
        } else if (ext === 'pdf') {
          const buffer = await readFileFromR2(fileUrl);
          const pdfParse = require('pdf-parse');
          const pdfData = await pdfParse(buffer);
          const pdfText = pdfData.text?.substring(0, 15000) || '[PDF kosong]';
          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            lastMsg.content += `\n\n--- Isi dokumen PDF: ${fileName} (${pdfData.numpages} halaman) ---\n${pdfText}\n--- Akhir dokumen ---`;
          }
        } else if (textExts.includes(ext)) {
          const buffer = await readFileFromR2(fileUrl);
          const fileContent = buffer.toString('utf-8').substring(0, 15000);
          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            lastMsg.content += `\n\n--- File: ${fileName} ---\n${fileContent}\n--- End of file ---`;
          }
        } else {
          const lastMsg = allMessages[allMessages.length - 1];
          if (lastMsg && lastMsg.role === 'user') {
            lastMsg.content += `\n\n[User melampirkan dokumen: ${fileName}. Analisis berdasarkan konteks percakapan.]`;
          }
        }
      } catch (fileErr) {
        metrics.inc('attachment_read_failures_total', { ext: ext || 'unknown' });
        logger.warn('message_attachment_read_failed', {
          request_id: req.requestId,
          index: i + 1,
          file_name: fileName,
          error: fileErr.message,
        });
        const lastMsg = allMessages[allMessages.length - 1];
        if (lastMsg && lastMsg.role === 'user') {
          lastMsg.content += `\n\n[File terlampir: ${fileName} - tidak dapat dibaca atau tidak ditemukan]`;
        }
      }
    }

    // After processing all files, assemble multimodal content if images exist
    if (useMultimodal && imageParts.length > 0) {
      const lastMsg = allMessages[allMessages.length - 1];
      if (lastMsg && lastMsg.role === 'user') {
        const textContent = typeof lastMsg.content === 'string' ? lastMsg.content : lastMsg.content;
        lastMsg.content = [
          { type: 'text', text: textContent },
          ...imageParts,
        ];
      }
    }

    const messages = [
      { role: 'system', content: getSystemPrompt(model, tools || []) },
      ...allMessages,
    ];

    const useStream = req.body.stream === true && (!tools || !tools.includes('browse_web'));

    // === SSE STREAMING MODE (non-browse only) ===
    if (useStream) {
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Accel-Buffering', 'no');
      res.flushHeaders();

      const aiResponse = await fetchAI({ model, messages, stream: true });

      if (!aiResponse.ok) {
        const errData = await aiResponse.json().catch(() => ({}));
        res.write(`data: ${JSON.stringify({ error: errData.error?.message || 'AI API error' })}\n\n`);
        res.write('data: [DONE]\n\n');
        return res.end();
      }

      let fullContent = '';
      const reader = aiResponse.body;

      // Handle image generation model — images come in non-standard format
      const isImageModel = model && model.includes('image');

      for await (const chunk of reader) {
        const text = typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf-8');
        const lines = text.split('\n').filter(l => l.startsWith('data: '));

        for (const line of lines) {
          const data = line.slice(6).trim();
          if (data === '[DONE]') continue;

          try {
            const parsed = JSON.parse(data);
            const delta = parsed.type === 'content_block_delta'
              ? (parsed.delta?.text || '')
              : (parsed.choices?.[0]?.delta?.content || '');
            if (delta) {
              fullContent += delta;
              res.write(`data: ${JSON.stringify({ token: delta })}\n\n`);
            }

            // Check for images (image generation models)
            const images = parsed.choices?.[0]?.message?.images || parsed.choices?.[0]?.delta?.images;
            if (images && Array.isArray(images) && images.length > 0) {
              res.write(`data: ${JSON.stringify({ images })}\n\n`);
            }
          } catch {}
        }
      }

      // Save AI response to DB
      const saved = await pool.query(
        `INSERT INTO messages (chat_id, role, content) VALUES ($1, 'assistant', $2) RETURNING *`,
        [req.params.chatId, fullContent]
      );

      // Auto-title on first message
      const msgCount = await pool.query(
        'SELECT COUNT(*) FROM messages WHERE chat_id = $1', [req.params.chatId]
      );
      const chatTitleUpdated = parseInt(msgCount.rows[0].count) <= 2;

      if (chatTitleUpdated) {
        try {
          const titleResponse = await fetchAI({
            model: TITLE_MODEL,
            messages: [{ role: 'user', content: `Buatkan judul singkat (maksimal 5 kata, tanpa tanda kutip) untuk percakapan yang dimulai dengan pesan ini: "${content}"` }],
            stream: false,
            max_tokens: 50,
          });
          if (titleResponse.ok) {
            const titleData = await titleResponse.json();
            const title = titleData.choices?.[0]?.message?.content?.trim().slice(0, 100) || content.slice(0, 50);
            await pool.query('UPDATE chats SET title = $1, updated_at = NOW() WHERE id = $2', [title, req.params.chatId]);
          }
        } catch {
          await pool.query('UPDATE chats SET title = $1, updated_at = NOW() WHERE id = $2', [content.slice(0, 50), req.params.chatId]);
        }
      } else {
        await pool.query('UPDATE chats SET updated_at = NOW() WHERE id = $1', [req.params.chatId]);
      }

      await recordUsage(req.userId, 'ai_request', 1, { model, stream: true });

      // Send final metadata
      res.write(`data: ${JSON.stringify({ done: true, message: saved.rows[0], chat_title_updated: chatTitleUpdated })}\n\n`);
      res.write('data: [DONE]\n\n');
      return res.end();
    }

    // === NON-STREAMING MODE (browse + fallback) ===
    const aiResponse = await fetchAI({ model, messages, stream: false });

    if (!aiResponse.ok) {
      const errData = await aiResponse.json().catch(() => ({}));
      throw new Error(errData.error?.message || 'AI API error');
    }

    const aiData = await aiResponse.json();
    const aiMsg = aiData.choices?.[0]?.message;
    let aiContent = aiMsg?.content || '';

    // === AGENTIC BROWSING LOOP ===
    if (tools && tools.includes('browse_web')) {
      const MAX_BROWSE_STEPS = 5;
      let browseMessages = [...messages];
      let currentResponse = aiContent;
      let browseScreenshots = [];

      for (let step = 0; step < MAX_BROWSE_STEPS; step++) {
        // Parse browse commands from AI response
        const commands = parseBrowseCommands(currentResponse);

        // FALLBACK: If AI model didn't emit any browse commands on first step,
        // auto-search using the user's message (makes browse work across ALL models)
        if (commands.length === 0 && step === 0) {
          const userMessages = allMessages.filter(m => m.role === 'user');
          const lastUserMsg = userMessages[userMessages.length - 1];
          const userText = typeof lastUserMsg?.content === 'string'
            ? lastUserMsg.content
            : (Array.isArray(lastUserMsg?.content)
                ? lastUserMsg.content.filter(c => c.type === 'text').map(c => c.text).join(' ')
                : '');

          if (userText && userText.length > 2) {
            logger.info('browse_fallback_search', { request_id: req.requestId });
            const searchResult = await executeSearch(userText.substring(0, 150));
            if (searchResult.resultCount > 0) {
              // Feed search results to AI and ask it to answer based on results
              browseMessages.push({ role: 'assistant', content: currentResponse });
              browseMessages.push({ role: 'user', content: `[Hasil pencarian otomatis]\n\n${searchResult.text}\n\nGunakan hasil pencarian di atas untuk menjawab pertanyaan sebelumnya dengan informasi terkini. Jika ingin membuka URL tertentu untuk detail lebih, gunakan [BROWSE:url].` });

              const retryResponse = await fetchAI({
                model,
                messages: browseMessages,
                stream: false,
              });
              if (retryResponse.ok) {
                const retryData = await retryResponse.json();
                currentResponse = retryData.choices?.[0]?.message?.content || currentResponse;
                aiContent = currentResponse;
                // Continue loop to check if AI now wants to browse further
                continue;
              }
            }
          }
          break;
        }

        if (commands.length === 0) break;

        logger.info('browse_step', {
          request_id: req.requestId,
          step: step + 1,
          command_count: commands.length,
        });

        // Execute each command
        let browseResults = [];
        for (const cmd of commands) {
          try {
            if (cmd.action === 'search') {
              // Direct HTTP search - no Puppeteer needed
              const searchResult = await executeSearch(cmd.query);
              browseResults.push(searchResult);
            } else {
              // Puppeteer-based browsing
              const browseResult = await executeBrowseCommand(cmd, req);
              browseResults.push(browseResult);
              if (browseResult.screenshot_url) {
                browseScreenshots.push(browseResult.screenshot_url);
              }
            }
          } catch (err) {
            browseResults.push({ error: err.message });
          }
        }

        // Build browse context for AI
        const browseContext = browseResults.map((r, i) => {
          let ctx = `--- Hasil (Step ${step + 1}, Command ${i + 1}) ---\n`;
          if (r.error) return ctx + `Error: ${r.error}`;

          // Search results (from HTTP fetch)
          if (r.type === 'search') {
            ctx += r.text;
            return ctx;
          }

          // Browse results (from Puppeteer)
          ctx += `URL: ${r.current_url || 'unknown'}\n`;
          ctx += `Title: ${r.page_title || 'unknown'}\n`;
          if (r.text_content) ctx += `Konten halaman:\n${r.text_content}\n`;
          if (r.elements && r.elements.length > 0) {
            ctx += `Elemen interaktif:\n`;
            r.elements.forEach(el => {
              if (el.type === 'link') ctx += `  - Link: "${el.text}" -> ${el.href}\n`;
              if (el.type === 'input') ctx += `  - Input: ${el.name} (selector: ${el.selector})\n`;
              if (el.type === 'button') ctx += `  - Button: "${el.text}"\n`;
            });
          }
          if (r.screenshot_url) ctx += `Screenshot: ${r.screenshot_url}\n`;
          return ctx;
        }).join('\n');

        // Add AI response + browse result to conversation
        browseMessages.push({ role: 'assistant', content: currentResponse });
        browseMessages.push({ role: 'user', content: `[Hasil browsing otomatis - gunakan informasi ini untuk menjawab]\n\n${browseContext}` });

        // Re-call AI with browse results
        const followUp = await fetchAI({
          model,
          messages: browseMessages,
          stream: false,
        });

        if (!followUp.ok) break;

        const followData = await followUp.json();
        currentResponse = followData.choices?.[0]?.message?.content || '';
        if (!currentResponse) break;
      }

      // Final response: strip any remaining browse commands and include screenshots
      aiContent = currentResponse;

      // Strip browse commands from final response
      aiContent = aiContent.replace(/\[BROWSE:[^\]]+\]/gi, '');
      aiContent = aiContent.replace(/\[SEARCH:[^\]]+\]/gi, '');
      aiContent = aiContent.replace(/\[CLICK:[^\]]+\]/gi, '');
      aiContent = aiContent.replace(/\[TYPE:[^\]]+\]/gi, '');
      aiContent = aiContent.replace(/\[SCROLL:(up|down)\]/gi, '');
      aiContent = aiContent.replace(/\[ENTER\]/gi, '');
      aiContent = aiContent.trim();

      if (browseScreenshots.length > 0) {
        const screenshotMd = browseScreenshots.map((url, i) =>
          `![Screenshot ${i + 1}](${url})`
        ).join('\n\n');
        if (!aiContent.includes('Screenshot')) {
          aiContent += '\n\n---\n📸 **Screenshots:**\n\n' + screenshotMd;
        }
      }

      // If browse ran but AI still returned empty, provide fallback
      if (!aiContent || aiContent.length < 10) {
        aiContent = 'Browsing selesai, tapi AI tidak memberikan ringkasan. Silakan coba lagi dengan pertanyaan yang lebih spesifik.';
      }
    }
    // === END BROWSING LOOP ===

    // Handle image generation: router returns images in message.images[]
    const images = aiMsg?.images;
    if (images && Array.isArray(images) && images.length > 0) {
      const { v4: uuidv4 } = require('uuid');
      const contentParts = [];

      if (aiContent) contentParts.push(aiContent);

      for (const img of images) {
        const imageUrl = img.image_url?.url || img.url || '';
        let mimeType;
        let buffer;

        try {
          if (imageUrl.startsWith('data:')) {
            const match = imageUrl.match(/^data:(image\/\w+);base64,(.+)$/s);
            if (!match) continue;
            mimeType = match[1];
            buffer = Buffer.from(match[2], 'base64');
          } else if (imageUrl.startsWith('https://')) {
            const imageResponse = await fetch(imageUrl);
            if (!imageResponse.ok) {
              throw new Error(`Image download failed: HTTP ${imageResponse.status}`);
            }
            mimeType = imageResponse.headers.get('content-type')?.split(';')[0] || 'image/png';
            if (!mimeType.startsWith('image/')) {
              throw new Error(`Unexpected image content type: ${mimeType}`);
            }
            buffer = Buffer.from(await imageResponse.arrayBuffer());
          } else {
            continue;
          }

          if (buffer.length > 20 * 1024 * 1024) {
            throw new Error('Generated image exceeds 20MB');
          }

          const ext = mimeType.split('/')[1] || 'png';
          const key = `generated/${req.userId}/${uuidv4()}.${ext}`;

          await s3Client.send(new PutObjectCommand({
            Bucket: process.env.R2_BUCKET_NAME,
            Key: key,
            Body: buffer,
            ContentType: mimeType,
          }));
          await recordFile({
            ownerId: req.userId,
            key,
            fileName: `generated.${ext}`,
            contentType: mimeType,
            size: buffer.length,
            visibility: 'public',
          });
          const baseUrl = process.env.PUBLIC_BASE_URL || 'https://askcore.dev';
          contentParts.push(`![Generated Image](${baseUrl}/api/files/${key})`);
        } catch (uploadErr) {
          metrics.inc('upload_failures_total', { code: 'GENERATED_IMAGE_SAVE_FAILED' });
          logger.warn('generated_image_save_failed', {
            request_id: req.requestId,
            error: uploadErr.message,
          });
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
        const titleResponse = await fetchAI({
          model: TITLE_MODEL,
          messages: [
            {
              role: 'user',
              content: `Buatkan judul singkat (maksimal 5 kata, tanpa tanda kutip) untuk percakapan yang dimulai dengan pesan ini: "${content}"`,
            },
          ],
          stream: false,
          max_tokens: 50,
        });
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

    await recordUsage(req.userId, 'ai_request', 1, { model, stream: false });
    if (tools && tools.includes('browse_web')) {
      await recordUsage(req.userId, 'browse_request', 1, { model, via: 'messages' });
    }
    if (modelInfo.supports_image_generation) {
      await recordUsage(req.userId, 'image_generation', 1, { model });
    }

    res.json({
      message: saved.rows[0],
      chat_title_updated: msgCount <= 1,
    });
  } catch (err) {
    logger.error('message_failed', {
      request_id: req.requestId,
      code: err.code || 'MESSAGE_FAILED',
      error: err.message || String(err),
    });
    if (!res.headersSent) {
      return sendError(res, req, err.statusCode || 500, err.message || 'Message failed', err);
    }
    try {
      res.write(`data: ${JSON.stringify({ error: 'Message failed', request_id: req.requestId })}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    } catch (e) {
      metrics.inc('sse_failures_total', { code: 'STREAM_CLOSE_FAILED' });
      logger.error('stream_close_failed', {
        request_id: req.requestId,
        error: e.message || String(e),
      });
    }
  }
});

module.exports = router;
