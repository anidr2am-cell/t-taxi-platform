/**
 * middlewares/error.middleware.js — Global error handler (must be last middleware)
 */
const logger = require('../utils/logger');
const config = require('../config');
const ERROR_CODES = require('../constants/errorCodes');
const {
  isDatabaseOrInternalError,
  resolveClientErrorMessage,
  isTripEndRequest,
  resolveStatusCode,
} = require('../utils/clientErrorMessage.util');

function errorMiddleware(err, req, res, next) {
  if (res.headersSent) {
    return next(err);
  }

  const isAppError = err.isOperational === true;
  const statusCode = resolveStatusCode(err);
  const errorCode = err.errorCode || ERROR_CODES.INTERNAL_SERVER_ERROR;
  const exposeInternalDetails = isDatabaseOrInternalError(err);

  if (!isAppError || statusCode >= 500) {
    logger.error(err.message, {
      stack: err.stack,
      path: req.path,
      method: req.method,
      code: err.code,
    });
  } else {
    logger.warn(err.message, { path: req.path, errorCode });
  }

  const body = {
    success: false,
    error_code: errorCode,
    message: resolveClientErrorMessage(err, {
      tripEndFailure: isTripEndRequest(req),
    }),
  };

  if (err.errors && config.server.nodeEnv !== 'production') {
    body.errors = err.errors;
  }

  if (config.server.nodeEnv === 'development' && !isAppError && !exposeInternalDetails) {
    body.stack = err.stack;
  }

  res.status(statusCode).json(body);
}

module.exports = errorMiddleware;
