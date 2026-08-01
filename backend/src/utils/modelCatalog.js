/**
 * Dynamic Model Catalog
 *
 * Models are sourced from the active router_configs entry (external LLM router)
 * and merged with per-model overrides stored in the `models` database table.
 *
 * Fallback order:
 *  1. Active router /v1/models endpoint (OpenAI-compatible format)
 *  2. Local `models` database table (for overrides / capability flags)
 *  3. Hardcoded MODELS array (offline / startup safety net)
 */

// Hardcoded fallback used only when both the router AND the database are unreachable.
const MODELS = [
  {
    id: 'mk/sonnet-4.5',
    owned_by: 'Anthropic',
    display_name: 'Claude Sonnet 4.5',
    supports_reasoning: true,
    supports_vision: true,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'premium',
    enabled: true,
  },
  {
    id: 'mk/haiku-4.5',
    owned_by: 'Anthropic',
    display_name: 'Claude Haiku 4.5',
    supports_reasoning: true,
    supports_vision: true,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'standard',
    enabled: true,
  },
  {
    id: 'wz/gpt-5.6-luna',
    owned_by: 'OpenAI',
    display_name: 'GPT 5.6 Luna',
    supports_reasoning: false,
    supports_vision: false,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'premium',
    enabled: true,
  },
  {
    id: 'kc/minimax-m3',
    owned_by: 'MiniMax',
    display_name: 'MiniMax M3',
    supports_reasoning: false,
    supports_vision: false,
    supports_image_generation: false,
    supports_browse: true,
    cost_tier: 'standard',
    enabled: true,
  },
];

// ─── Database connection ──────────────────────────────────────────────────────
const { pool } = require('../db');

// ─── Cache ────────────────────────────────────────────────────────────────────
let modelsCache = null;
let lastCacheUpdate = 0;
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

// ─── Helper: derive a human-friendly display name from a model id ─────────────
function _displayNameFromId(modelId) {
  // e.g. "bm/K1/claude-sonnet-5" → "Claude Sonnet 5"
  const parts = modelId.split('/');
  const raw = parts[parts.length - 1] || modelId;
  return raw
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

// ─── Helper: guess provider from model id prefix ─────────────────────────────
function _providerFromId(modelId) {
  const prefix = modelId.split('/')[0];
  const map = {
    mk: 'Anthropic',
    bm: 'OpenRouter',
    cv: 'OpenAI',
    kc: 'KimiChain',
    wz: 'WuZhi',
    qc: 'QwenChain',
    dh: 'DongHai',
    at: 'AT-Router',
  };
  return map[prefix] || prefix.toUpperCase();
}

// ─── Helper: guess capabilities from model id ────────────────────────────────
function _guessCapabilities(modelId) {
  const lower = modelId.toLowerCase();
  const isVision = /vision|vl|multimodal|phi-4-multimodal|llama.*vision/i.test(lower);
  const isImage = /image|wan2|z-image/i.test(lower);
  const isImageEdit = /image.edit/i.test(lower);
  const isReasoning = /thinking|reason|o1|o3|opus.*thinking/i.test(lower);
  const isCode = /code|coder|codestral|starcoder|granite.*code/i.test(lower);

  return {
    supports_reasoning: isReasoning,
    supports_vision: isVision || isImageEdit,
    supports_image_generation: isImage || isImageEdit,
    supports_browse: !isImage && !isImageEdit,
    cost_tier: isImage || isImageEdit ? 'image' : 'standard',
  };
}

// ─── Helper: fetch models from the active router ─────────────────────────────
async function _fetchRouterModels() {
  try {
    // Find the active router config
    const configResult = await pool.query(
      `SELECT base_url, api_key, timeout_ms FROM router_configs
       WHERE is_active = true
       ORDER BY id ASC LIMIT 1`
    );

    if (!configResult.rows.length) return null;

    const config = configResult.rows[0];
    const timeout = config.timeout_ms || 15000;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);

    try {
      const response = await fetch(`${config.base_url}/v1/models`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${config.api_key}`,
          'Content-Type': 'application/json',
        },
        signal: controller.signal,
      });

      clearTimeout(timer);

      if (!response.ok) {
        console.error(`Router /v1/models returned ${response.status}`);
        return null;
      }

      const data = await response.json();
      const routerModels = (data.data || []).map((m) => ({
        id: m.id,
        owned_by: _providerFromId(m.id),
        display_name: _displayNameFromId(m.id),
        ..._guessCapabilities(m.id),
        enabled: true,
        source: 'router',
      }));

      return routerModels;
    } catch (fetchErr) {
      clearTimeout(timer);
      if (fetchErr.name === 'AbortError') {
        console.error('Router /v1/models timed out');
      } else {
        console.error('Router /v1/models fetch error:', fetchErr.message);
      }
      return null;
    }
  } catch (err) {
    console.error('Failed to query router_configs:', err.message);
    return null;
  }
}

// ─── Helper: load DB overrides from the `models` table ───────────────────────
async function _loadDbOverrides() {
  try {
    const result = await pool.query('SELECT * FROM models WHERE enabled = true ORDER BY display_name ASC');
    return result.rows;
  } catch (err) {
    console.error('Failed to load models from database:', err.message);
    return [];
  }
}

// ─── Core: build the merged model catalog ────────────────────────────────────
async function refreshModelsCache() {
  // 1. Try fetching from the external router
  const routerModels = await _fetchRouterModels();

  // 2. Load DB overrides (capability flags, display name tweaks, etc.)
  const dbModels = await _loadDbOverrides();

  if (routerModels && routerModels.length > 0) {
    // Build a lookup map from DB overrides by model id
    const dbOverrideMap = new Map();
    for (const dbm of dbModels) {
      dbOverrideMap.set(dbm.id, dbm);
    }

    // Merge: router models as the source of truth, DB overrides for metadata
    const merged = routerModels.map((rm) => {
      const override = dbOverrideMap.get(rm.id);
      if (override) {
        return {
          id: rm.id,
          owned_by: override.owned_by || rm.owned_by,
          display_name: override.display_name || rm.display_name,
          supports_reasoning: override.supports_reasoning ?? rm.supports_reasoning,
          supports_vision: override.supports_vision ?? rm.supports_vision,
          supports_image_generation: override.supports_image_generation ?? rm.supports_image_generation,
          supports_browse: override.supports_browse ?? rm.supports_browse,
          cost_tier: override.cost_tier || rm.cost_tier,
          enabled: override.enabled !== false,
          source: 'router+db',
        };
      }
      return rm;
    });

    // Also include any DB-only models not on the router (custom / manually added)
    for (const dbm of dbModels) {
      if (!merged.some((m) => m.id === dbm.id)) {
        merged.push({ ...dbm, source: 'db' });
      }
    }

    modelsCache = merged;
  } else if (dbModels.length > 0) {
    // Router unreachable — fall back to DB-only
    modelsCache = dbModels;
  } else {
    // Both router and DB unavailable — use hardcoded fallback
    modelsCache = MODELS.filter((m) => m.enabled);
  }

  lastCacheUpdate = Date.now();
}

async function getModelsFromDB() {
  if (!modelsCache || Date.now() - lastCacheUpdate > CACHE_TTL) {
    await refreshModelsCache();
  }
  return modelsCache;
}

async function listModels() {
  try {
    return await getModelsFromDB();
  } catch (err) {
    console.error('listModels fallback:', err.message);
    return MODELS.filter((model) => model.enabled);
  }
}

async function findModel(id) {
  try {
    const models = await getModelsFromDB();
    return models.find((model) => model.id === id) || null;
  } catch (err) {
    return MODELS.find((model) => model.id === id && model.enabled) || null;
  }
}

async function assertValidModel(id) {
  const model = await findModel(id);
  if (!model) {
    const err = new Error('Model is not available');
    err.statusCode = 400;
    err.code = 'MODEL_NOT_AVAILABLE';
    throw err;
  }
  return model;
}

/** Force-refresh the cache (e.g. after admin changes router config). */
function invalidateCache() {
  modelsCache = null;
  lastCacheUpdate = 0;
}

module.exports = { MODELS, listModels, findModel, assertValidModel, invalidateCache, refreshModelsCache };
