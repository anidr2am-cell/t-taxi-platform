/**
 * middlewares/requestLogger.middleware.js — Log every HTTP request
 */
const logger = require('../utils/logger');

function requestLoggerMiddleware(req, res, next) {
  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    logger.info(`${req.method} ${req.originalUrl} ${res.statusCode} ${ms}ms`);
  });
  next();
}

module.exports = requestLoggerMiddleware;
