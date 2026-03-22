const express = require('express');
const authMiddleware = require('../middleware/auth');

const router = express.Router();
router.use(authMiddleware);

// Shared browser instance (singleton to save RAM)
let browserInstance = null;
let browserIdleTimer = null;
const BROWSER_IDLE_TIMEOUT = 120000; // 2 minutes

async function getBrowser() {
  if (browserInstance) {
    resetIdleTimer();
    return browserInstance;
  }

  const puppeteer = require('puppeteer');
  browserInstance = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--single-process',
      '--no-zygote',
      '--disable-extensions',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-backgrounding-occluded-windows',
    ],
    executablePath: process.env.CHROME_PATH || undefined,
  });

  console.log('[BROWSE] Browser launched');
  resetIdleTimer();
  return browserInstance;
}

function resetIdleTimer() {
  if (browserIdleTimer) clearTimeout(browserIdleTimer);
  browserIdleTimer = setTimeout(async () => {
    if (browserInstance) {
      try {
        await browserInstance.close();
        console.log('[BROWSE] Browser closed (idle timeout)');
      } catch (_) {}
      browserInstance = null;
    }
  }, BROWSER_IDLE_TIMEOUT);
}

// Browse endpoint: navigate, screenshot, extract text
router.post('/', async (req, res) => {
  const { url, action = 'navigate', selector, text, scroll_direction } = req.body;

  if (!url && action === 'navigate') {
    return res.status(400).json({ error: 'URL required for navigate action' });
  }

  try {
    const browser = await getBrowser();
    const pages = await browser.pages();
    let page = pages.length > 0 ? pages[pages.length - 1] : await browser.newPage();

    // Set viewport
    await page.setViewport({ width: 1280, height: 800 });

    let result = {};

    switch (action) {
      case 'navigate': {
        const targetUrl = url.startsWith('http') ? url : `https://${url}`;
        await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
        await page.waitForTimeout(1000); // Let page render
        break;
      }
      case 'click': {
        if (selector) {
          await page.click(selector);
          await page.waitForTimeout(1000);
        }
        break;
      }
      case 'type': {
        if (selector && text) {
          await page.type(selector, text, { delay: 50 });
          await page.waitForTimeout(500);
        }
        break;
      }
      case 'scroll': {
        const direction = scroll_direction === 'up' ? -500 : 500;
        await page.evaluate((d) => window.scrollBy(0, d), direction);
        await page.waitForTimeout(500);
        break;
      }
      case 'press_enter': {
        await page.keyboard.press('Enter');
        await page.waitForTimeout(2000);
        break;
      }
    }

    // Take screenshot
    const screenshotBuffer = await page.screenshot({
      type: 'jpeg',
      quality: 60,
      fullPage: false,
    });

    // Upload screenshot to R2
    const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
    const s3 = new S3Client({
      region: 'auto',
      endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
      },
    });

    const key = `browse/${req.userId}/${Date.now()}.jpg`;
    await s3.send(new PutObjectCommand({
      Bucket: process.env.R2_BUCKET_NAME,
      Key: key,
      Body: screenshotBuffer,
      ContentType: 'image/jpeg',
    }));

    const proto = req.get('x-forwarded-proto') || req.protocol;
    const host = req.get('x-forwarded-host') || req.get('host');
    const screenshotUrl = `${proto}://${host}/api/files/${key}`;

    // Extract page info
    const pageTitle = await page.title();
    const currentUrl = page.url();

    // Extract visible text (limited to first 3000 chars)
    const pageText = await page.evaluate(() => {
      const body = document.body;
      if (!body) return '';
      // Remove scripts and styles
      const clone = body.cloneNode(true);
      clone.querySelectorAll('script, style, noscript, svg').forEach(el => el.remove());
      return clone.innerText?.substring(0, 3000) || '';
    });

    // Extract interactive elements (links, buttons, inputs)
    const elements = await page.evaluate(() => {
      const items = [];
      // Links
      document.querySelectorAll('a[href]').forEach((el, i) => {
        if (i < 10 && el.innerText?.trim()) {
          items.push({ type: 'link', text: el.innerText.trim().substring(0, 80), href: el.href });
        }
      });
      // Inputs
      document.querySelectorAll('input, textarea').forEach((el, i) => {
        if (i < 5) {
          items.push({
            type: 'input',
            name: el.name || el.placeholder || el.type,
            selector: el.id ? `#${el.id}` : `input[name="${el.name}"]`,
          });
        }
      });
      // Buttons
      document.querySelectorAll('button, [role="button"]').forEach((el, i) => {
        if (i < 5 && el.innerText?.trim()) {
          items.push({ type: 'button', text: el.innerText.trim().substring(0, 50) });
        }
      });
      return items;
    });

    result = {
      screenshot_url: screenshotUrl,
      page_title: pageTitle,
      current_url: currentUrl,
      text_content: pageText,
      elements: elements,
    };

    res.json(result);
  } catch (err) {
    console.error('[BROWSE ERROR]', err.message);
    res.status(500).json({ error: `Browse failed: ${err.message}` });
  }
});

// Close browser manually
router.delete('/', async (req, res) => {
  if (browserInstance) {
    await browserInstance.close();
    browserInstance = null;
    if (browserIdleTimer) clearTimeout(browserIdleTimer);
  }
  res.json({ status: 'browser closed' });
});

module.exports = router;
