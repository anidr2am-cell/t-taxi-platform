/**
 * middlewares/notFound.middleware.js — 404 for unknown routes
 */
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function notFoundMiddleware(req, res, next) {
  next(
    new AppError(`Route not found: ${req.method} ${req.originalUrl}`, {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.NOT_FOUND,
    }),
  );
}

module.exports = notFoundMiddleware;
