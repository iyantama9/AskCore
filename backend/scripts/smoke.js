#!/usr/bin/env node

function readArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) return null;
  return process.argv[index + 1];
}

const BASE_URL = (
  readArg('--base-url') ||
  process.env.SMOKE_BASE_URL ||
  process.env.PUBLIC_BASE_URL ||
  'https://askcore.dev'
).replace(/\/$/, '');
const USERNAME = process.env.SMOKE_USERNAME;
const PASSWORD = process.env.SMOKE_PASSWORD;
const RUN_AUTH_FLOW = Boolean(USERNAME && PASSWORD);

async function request(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.SMOKE_TIMEOUT_MS || 15000));

  try {
    const response = await fetch(`${BASE_URL}${path}`, {
      ...options,
      signal: controller.signal,
      headers: {
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...(options.headers || {}),
      },
    });
    const text = await response.text();
    let body;
    try {
      body = text ? JSON.parse(text) : null;
    } catch (_) {
      body = text;
    }
    return { response, body };
  } finally {
    clearTimeout(timeout);
  }
}

async function assertOk(name, fn) {
  try {
    await fn();
    console.log(`✓ ${name}`);
  } catch (err) {
    console.error(`✗ ${name}`);
    console.error(`  ${err.message}`);
    process.exitCode = 1;
  }
}

function expectStatus(result, expected, label) {
  if (result.response.status !== expected) {
    throw new Error(`${label} returned ${result.response.status}: ${JSON.stringify(result.body)}`);
  }
}

async function main() {
  console.log(`Smoke target: ${BASE_URL}`);

  await assertOk('liveness endpoint', async () => {
    const result = await request('/api/health/live');
    expectStatus(result, 200, 'liveness');
    if (result.body?.status !== 'ok') throw new Error(`unexpected liveness body: ${JSON.stringify(result.body)}`);
  });

  await assertOk('readiness endpoint', async () => {
    const result = await request('/api/health/ready');
    expectStatus(result, 200, 'readiness');
    if (result.body?.status !== 'ok') throw new Error(`unexpected readiness body: ${JSON.stringify(result.body)}`);
  });

  await assertOk('unauthenticated chats are rejected', async () => {
    const result = await request('/api/chats');
    expectStatus(result, 401, 'unauthenticated chats');
  });

  await assertOk('blocked SSRF URL fails safely', async () => {
    const result = await request('/api/browse', {
      method: 'POST',
      body: JSON.stringify({ url: 'http://127.0.0.1', action: 'navigate' }),
      headers: { Authorization: 'Bearer invalid-smoke-token' },
    });
    expectStatus(result, 401, 'browse auth guard');
  });

  if (!RUN_AUTH_FLOW) {
    console.log('ℹ Set SMOKE_USERNAME and SMOKE_PASSWORD to run authenticated smoke checks.');
    return;
  }

  let token;
  let chatId;

  await assertOk('login smoke user', async () => {
    const result = await request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username: USERNAME, password: PASSWORD }),
    });
    expectStatus(result, 200, 'login');
    token = result.body?.token;
    if (!token) throw new Error('login did not return token');
  });

  await assertOk('create smoke chat', async () => {
    const result = await request('/api/chats', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: JSON.stringify({ title: 'Smoke Test', model: 'mk/sonnet-4.5' }),
    });
    expectStatus(result, 201, 'create chat');
    chatId = result.body?.id;
    if (!chatId) throw new Error('create chat did not return id');
  });

  await assertOk('send smoke prompt', async () => {
    const result = await request(`/api/chats/${chatId}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: JSON.stringify({ content: 'Balas singkat: smoke test OK' }),
    });
    expectStatus(result, 200, 'send message');
    if (!result.body?.message?.content) throw new Error('send message did not return assistant content');
  });

  await assertOk('delete smoke chat', async () => {
    const result = await request(`/api/chats/${chatId}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    expectStatus(result, 200, 'delete chat');
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
