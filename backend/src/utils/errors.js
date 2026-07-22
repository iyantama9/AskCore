const logger = require('./logger');
const { randomUUID } = require('crypto');

function requestIdMiddleware(req, res, next) {
  const incoming = req.get('x-request-id');
  req.requestId = incoming && incoming.length <= 80 ? incoming : randomUUID();
  res.setHeader('X-Request-ID', req.requestId);
  next();
}

function safeError(message, req, code = 'ERROR') {
  return {
    error: message,
    code,
    request_id: req?.requestId,
  };
}

function sendError(res, req, status, publicMessage, err, code) {
  const errorCode = code || err?.code || statusToCode(status);
  res.locals.errorCode = errorCode;
  if (err) {
    logger.error(publicMessage, {
      request_id: req?.requestId,
      code: errorCode,
      status,
      error: err.message || String(err),
      stack: process.env.NODE_ENV === 'production' ? undefined : err.stack,
    });
  }
  return res.status(status).json(safeError(publicMessage, req, errorCode));
}

function statusToCode(status) {
  if (status === 400) return 'BAD_REQUEST';
  if (status === 401) return 'UNAUTHORIZED';
  if (status === 403) return 'FORBIDDEN';
  if (status === 404) return 'NOT_FOUND';
  if (status === 409) return 'CONFLICT';
  if (status === 429) return 'RATE_LIMITED';
  if (status === 503) return 'SERVICE_UNAVAILABLE';
  return 'SERVER_ERROR';
}

function notFoundHandler(req, res) {
  return sendError(res, req, 404, 'Route not found', null, 'ROUTE_NOT_FOUND');
}

function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);
  return sendError(
    res,
    req,
    err.statusCode || err.status || 500,
    err.publicMessage || 'Server error',
    err,
    err.code
  );
}

module.exports = {
  requestIdMiddleware,
  safeError,
  sendError,
  statusToCode,
  notFoundHandler,
  errorHandler,
};
