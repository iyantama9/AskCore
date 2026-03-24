const express = require('express');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');

const router = express.Router();
router.use(authMiddleware);

// --- Browse helpers ---

// Direct HTTP search via DuckDuckGo Lite (no Puppeteer = no CAPTCHA)
async function executeSearch(query) {
  try {
    const url = `https://lite.duckduckgo.com/lite/?q=${encodeURIComponent(query)}`;
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Accept': 'text/html',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    });
    const html = await resp.text();

    // Parse search results from DuckDuckGo Lite HTML
    const results = [];
    // DuckDuckGo Lite uses <a> tags with class="result-link" or simple <a href> in result rows
    const linkRegex = /<a[^>]+rel="nofollow"[^>]+href="([^"]+)"[^>]*>([^<]+)<\/a>/gi;
    const snippetRegex = /<td[^>]*class="result-snippet"[^>]*>([\s\S]*?)<\/td>/gi;

    let match;
    while ((match = linkRegex.exec(html)) !== null) {
      const href = match[1];
      const title = match[2].replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#x27;/g, "'").trim();
      if (href.startsWith('http') && !href.includes('duckduckgo.com')) {
        results.push({ title, url: href, snippet: '' });
      }
    }

    // Try to get snippets
    let snippetMatch;
    let idx = 0;
    while ((snippetMatch = snippetRegex.exec(html)) !== null && idx < results.length) {
      results[idx].snippet = snippetMatch[1].replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').trim().substring(0, 200);
      idx++;
    }

    // Format results as text for AI
    if (results.length === 0) {
      // Fallback: extract any <a href> links from the page
      const fallbackRegex = /<a[^>]+href="(https?:\/\/[^"]+)"[^>]*>([^<]+)<\/a>/gi;
      while ((match = fallbackRegex.exec(html)) !== null && results.length < 10) {
        const href = match[1];
        const title = match[2].trim();
        if (!href.includes('duckduckgo.com') && title.length > 5) {
          results.push({ title, url: href, snippet: '' });
        }
      }
    }

    const top = results.slice(0, 10);
    let text = `Hasil pencarian untuk "${query}":\n\n`;
    top.forEach((r, i) => {
      text += `${i + 1}. ${r.title}\n   URL: ${r.url}\n`;
      if (r.snippet) text += `   ${r.snippet}\n`;
      text += '\n';
    });

    console.log(`[SEARCH] Found ${top.length} results for: ${query}`);
    return { type: 'search', query, results: top, text, resultCount: top.length };
  } catch (err) {
    console.error('[SEARCH ERROR]', err.message);
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

  console.log('[BROWSE] Stealth browser launched');
  sharedIdleTimer = setTimeout(async () => {
    try { await sharedBrowser.close(); } catch(_) {}
    sharedBrowser = null;
  }, 120000);

  return sharedBrowser;
}

async function executeBrowseCommand(cmd, req) {
  const browser = await getSharedBrowser();
  const pages = await browser.pages();
  let page = pages.length > 0 ? pages[pages.length - 1] : await browser.newPage();
  // Set realistic user agent to bypass bot detection
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36');
  await page.setViewport({ width: 1280, height: 800 });

  switch (cmd.action) {
    case 'navigate': {
      const url = cmd.url.startsWith('http') ? cmd.url : `https://${cmd.url}`;
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
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
  const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
  const s3 = new S3Client({
    region: 'auto',
    endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId: process.env.R2_ACCESS_KEY_ID, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY },
  });
  const key = `browse/${req.userId}/${Date.now()}.jpg`;
  await s3.send(new PutObjectCommand({
    Bucket: process.env.R2_BUCKET_NAME, Key: key, Body: screenshotBuffer, ContentType: 'image/jpeg',
  }));
  const proto = req.get('x-forwarded-proto') || req.protocol;
  const host = req.get('x-forwarded-host') || req.get('host');

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
    screenshot_url: `${proto}://${host}/api/files/${key}`,
    page_title: await page.title().catch(() => ''),
    current_url: page.url(),
    text_content: pageText,
    elements,
  };
}
// --- End browse helpers ---

const getSystemPrompt = (model, tools = []) => {
  let base = 'Jawab dalam Bahasa Indonesia kecuali user meminta bahasa lain. Gunakan format markdown jika diperlukan. Jika user melampirkan file (gambar, PDF, kode, dll), isi file tersebut sudah diekstrak dan disertakan langsung di dalam pesan user. Kamu BISA membaca dan menganalisis konten file tersebut.';

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
  const { content, file_url, file_name, file_urls, file_names, tools } = req.body;

  if (!content || !content.trim()) {
    return res.status(400).json({ error: 'Content required' });
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
      return res.status(404).json({ error: 'Chat not found' });
    }

    const model = chat.rows[0].model;

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

    // Process all attached files for the AI
    let useMultimodal = false;
    const imageParts = []; // Collect all image parts for multimodal

    for (let i = 0; i < urls.length; i++) {
      const fileUrl = urls[i];
      const fileName = names[i] || 'file';
      console.log(`[FILE ${i + 1}/${urls.length}] file_url:`, fileUrl, 'file_name:', fileName);

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
        console.error(`[FILE ERROR ${i}]`, fileErr.message);
        const lastMsg = allMessages[allMessages.length - 1];
        if (lastMsg && lastMsg.role === 'user') {
          lastMsg.content += `\n\n[File terlampir: ${fileName} - Error: ${fileErr.message}]`;
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

    // === AGENTIC BROWSING LOOP ===
    if (tools && tools.includes('browse_web')) {
      const MAX_BROWSE_STEPS = 5;
      let browseMessages = [...messages];
      let currentResponse = aiContent;
      let browseScreenshots = [];

      for (let step = 0; step < MAX_BROWSE_STEPS; step++) {
        // Parse browse commands from AI response
        const commands = parseBrowseCommands(currentResponse);
        if (commands.length === 0) break;

        console.log(`[BROWSE] Step ${step + 1}: ${commands.length} command(s)`);

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
        const followUp = await fetch(`${process.env.AI_BASE_URL}/chat/completions`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${process.env.AI_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ model, messages: browseMessages, stream: false }),
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
      const { PutObjectCommand } = require('@aws-sdk/client-s3');
      const { v4: uuidv4 } = require('uuid');
      const contentParts = [];

      if (aiContent) contentParts.push(aiContent);

      for (const img of images) {
        const dataUrl = img.image_url?.url || img.url || '';
        if (!dataUrl.startsWith('data:')) continue;

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
          const proto = req.get('x-forwarded-proto') || req.protocol;
          const host = req.get('x-forwarded-host') || req.get('host');
          const baseUrl = `${proto}://${host}`;
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
