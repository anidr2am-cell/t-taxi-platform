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
    const validationErrors = errorCode === ERROR_CODES.VALIDATION_ERROR && Array.isArray(err.errors)
      ? err.errors.map((item) => ({
        field: item.field,
        type: item.type,
        source: item.source,
      }))
      : undefined;
    logger.warn(err.message, { path: req.path, errorCode, validationErrors });
  }

  const body = {
    success: false,
    error_code: errorCode,
    code: errorCode,
    message: resolveClientErrorMessage(err, {
      tripEndFailure: isTripEndRequest(req),
    }),
  };

<<<<<<< Updated upstream
  if (err.errors && (config.server.nodeEnv !== 'production' || errorCode === ERROR_CODES.VALIDATION_ERROR)) {
=======
  if (
    err.errors &&
    (config.server.nodeEnv !== 'production' || errorCode === ERROR_CODES.VALIDATION_ERROR)
  ) {
>>>>>>> Stashed changes
    body.errors = err.errors;
  }

  if (config.server.nodeEnv === 'development' && !isAppError && !exposeInternalDetails) {
    body.stack = err.stack;
  }

  res.status(statusCode).json(body);
}

module.exports = errorMiddleware;
