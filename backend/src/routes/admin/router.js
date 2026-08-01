const express = require('express');
const { pool } = require('../../db');
const authMiddleware = require('../../middleware/auth');
const { adminOnly } = require('../../middleware/admin');
const { sendError } = require('../../utils/errors');
const logger = require('../../utils/logger');
const { invalidateCache, refreshModelsCache } = require('../../utils/modelCatalog');

const router = express.Router();
router.use(authMiddleware);
router.use(adminOnly);

// Get all router configs
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, base_url, is_active, timeout_ms, max_retries,
              last_tested_at, last_test_status, created_at, updated_at
       FROM router_configs
       ORDER BY is_active DESC, name ASC`
    );
    res.json({ configs: result.rows });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch router configs', err);
  }
});

// Get single router config
router.get('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, base_url, api_key, is_active, timeout_ms,
              max_retries, metadata, last_tested_at, last_test_status,
              created_at, updated_at
       FROM router_configs
       WHERE id = $1`,
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Router config not found', null, 'CONFIG_NOT_FOUND');
    }

    res.json({ config: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch router config', err);
  }
});

// Create router config
router.post('/', async (req, res) => {
  const { name, base_url, api_key, timeout_ms, max_retries, metadata } = req.body;

  if (!name || !base_url || !api_key) {
    return sendError(res, req, 400, 'Missing required fields: name, base_url, api_key', null, 'MISSING_FIELDS');
  }

  try {
    const result = await pool.query(
      `INSERT INTO router_configs (name, base_url, api_key, timeout_ms, max_retries, metadata)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, name, base_url, is_active, timeout_ms, max_retries, created_at, updated_at`,
      [name, base_url, api_key, timeout_ms || 30000, max_retries || 3, JSON.stringify(metadata || {})]
    );

    res.status(201).json({ config: result.rows[0] });
    invalidateCache();
  } catch (err) {
    if (err.code === '23505') {
      return sendError(res, req, 409, 'Router config name already exists', err, 'CONFIG_EXISTS');
    }
    return sendError(res, req, 500, 'Failed to create router config', err);
  }
});

// Update router config
router.put('/:id', async (req, res) => {
  const { name, base_url, api_key, is_active, timeout_ms, max_retries, metadata } = req.body;

  try {
    const result = await pool.query(
      `UPDATE router_configs SET
        name = COALESCE($2, name),
        base_url = COALESCE($3, base_url),
        api_key = COALESCE($4, api_key),
        is_active = COALESCE($5, is_active),
        timeout_ms = COALESCE($6, timeout_ms),
        max_retries = COALESCE($7, max_retries),
        metadata = COALESCE($8, metadata),
        updated_at = NOW()
      WHERE id = $1
      RETURNING id, name, base_url, is_active, timeout_ms, max_retries, metadata, updated_at`,
      [req.params.id, name, base_url, api_key, is_active, timeout_ms, max_retries, metadata ? JSON.stringify(metadata) : null]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Router config not found', null, 'CONFIG_NOT_FOUND');
    }

    res.json({ config: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') {
      return sendError(res, req, 409, 'Router config name already exists', err, 'CONFIG_EXISTS');
    }
    return sendError(res, req, 500, 'Failed to update router config', err);
  }
});

// Delete router config
router.delete('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM router_configs WHERE id = $1 RETURNING id',
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Router config not found', null, 'CONFIG_NOT_FOUND');
    }

    res.json({ success: true, deleted_id: result.rows[0].id });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to delete router config', err);
  }
});

// Test router connection
router.post('/:id/test', async (req, res) => {
  try {
    const configResult = await pool.query(
      'SELECT base_url, api_key, timeout_ms FROM router_configs WHERE id = $1',
      [req.params.id]
    );

    if (!configResult.rows.length) {
      return sendError(res, req, 404, 'Router config not found', null, 'CONFIG_NOT_FOUND');
    }

    const config = configResult.rows[0];
    const startTime = Date.now();

    // Test connection with a simple health check or model list request
    const response = await fetch(`${config.base_url}/health`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${config.api_key}`,
      },
      signal: AbortSignal.timeout(config.timeout_ms),
    });

    const duration = Date.now() - startTime;
    const status = response.ok ? 'success' : 'failed';

    // Update last test results
    await pool.query(
      `UPDATE router_configs SET
        last_tested_at = NOW(),
        last_test_status = $2,
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{last_test_duration_ms}', $3::text::jsonb)
       WHERE id = $1`,
      [req.params.id, status, duration]
    );

    res.json({
      success: response.ok,
      status: response.status,
      duration_ms: duration,
      message: response.ok ? 'Connection successful' : 'Connection failed',
    });
  } catch (err) {
    logger.error('router_test_failed', { error: err.message, config_id: req.params.id });

    // Update test failure
    await pool.query(
      'UPDATE router_configs SET last_tested_at = NOW(), last_test_status = $2 WHERE id = $1',
      [req.params.id, 'error']
    );

    return sendError(res, req, 500, `Router test failed: ${err.message}`, err);
  }
});

// Toggle router active/inactive
router.patch('/:id/toggle', async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE router_configs SET is_active = NOT is_active, updated_at = NOW()
       WHERE id = $1
       RETURNING id, name, is_active`,
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Router config not found', null, 'CONFIG_NOT_FOUND');
    }

    res.json({ config: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to toggle router config', err);
  }
});

// Sync models from active router (force refresh model catalog)
router.post('/sync-models', async (req, res) => {
  try {
    invalidateCache();
    await refreshModelsCache();
    const { listModels } = require('../../utils/modelCatalog');
    const models = await listModels();
    res.json({
      success: true,
      message: `Synced ${models.length} models from router`,
      count: models.length,
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to sync models from router', err);
  }
});

module.exports = router;
