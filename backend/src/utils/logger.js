const metrics = require('./metrics');

function redact(value) {
  if (value == null) return value;
  const text = String(value);
  if (text.length <= 8) return '[redacted]';
  return `${text.slice(0, 4)}…${text.slice(-4)}`;
}

function write(level, message, fields = {}) {
  const entry = {
    ts: new Date().toISOString(),
    level,
    message,
    ...fields,
  };
  process[level === 'error' ? 'stderr' : 'stdout'].write(`${JSON.stringify(entry)}\n`);
}

function info(message, fields) {
  write('info', message, fields);
}

function warn(message, fields) {
  write('warn', message, fields);
}

function error(message, fields) {
  write('error', message, fields);
}

function requestLogger(req, res, next) {
  const started = process.hrtime.bigint();
  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - started) / 1_000_000;
    const userId = req.userId ? redact(req.userId) : undefined;
    const route = req.route?.path || req.path;
    const errorCode = res.locals.errorCode;
    metrics.inc('http_requests_total', {
      method: req.method,
      status: String(res.statusCode),
      route,
    });
    metrics.observe('http_request_duration_ms', durationMs, {
      method: req.method,
      status: String(res.statusCode),
      route,
    });
    if (res.statusCode >= 500) {
      metrics.inc('http_5xx_total', { route, code: errorCode || 'SERVER_ERROR' });
    }

    write(res.statusCode >= 500 ? 'error' : 'info', 'http_request', {
      request_id: req.requestId,
      method: req.method,
      path: req.originalUrl,
      route,
      status: res.statusCode,
      duration_ms: Number(durationMs.toFixed(1)),
      user_id: userId,
      error_code: errorCode,
    });
  });
  next();
}

module.exports = { info, warn, error, requestLogger, redact };
