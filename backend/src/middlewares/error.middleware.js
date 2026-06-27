/**
 * middlewares/error.middleware.js — Global error handler (must be last middleware)
 */
const logger = require('../utils/logger');
const config = require('../config');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function errorMiddleware(err, req, res, next) {
  if (res.headersSent) {
    return next(err);
  }

  const isAppError = err.isOperational === true;
  const statusCode = err.statusCode || HTTP_STATUS.INTERNAL_SERVER_ERROR;
  const errorCode = err.errorCode || ERROR_CODES.INTERNAL_SERVER_ERROR;

  if (!isAppError || statusCode >= 500) {
    logger.error(err.message, {
      stack: err.stack,
      path: req.path,
      method: req.method,
    });
  } else {
    logger.warn(err.message, { path: req.path, errorCode });
  }

  const body = {
    success: false,
    error_code: errorCode,
    message: err.message || 'Internal server error',
  };

  if (err.errors) {
    body.errors = err.errors;
  }

  if (config.server.nodeEnv === 'development' && !isAppError) {
    body.stack = err.stack;
  }

  res.status(statusCode).json(body);
}

module.exports = errorMiddleware;
