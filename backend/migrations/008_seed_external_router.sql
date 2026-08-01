-- Seed the external LLM router config
-- This replaces the localhost default with the actual production router.
INSERT INTO router_configs (name, base_url, api_key, is_active, timeout_ms, max_retries)
VALUES (
  'Iyan Router',
  'https://routers.iyantama.tech',
  'rotersganteng',
  true,
  15000,
  3
)
ON CONFLICT (name) DO UPDATE SET
  base_url = EXCLUDED.base_url,
  api_key = EXCLUDED.api_key,
  is_active = EXCLUDED.is_active,
  timeout_ms = EXCLUDED.timeout_ms,
  updated_at = NOW();

-- Deactivate any stale localhost default if it exists
UPDATE router_configs
SET is_active = false, updated_at = NOW()
WHERE base_url LIKE 'http://localhost%'
  AND name != 'Iyan Router';
