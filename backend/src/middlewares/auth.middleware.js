/**
 * middlewares/auth.middleware.js — JWT verification
 */
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const container = require('../helpers/container');

function authMiddleware(req, res, next) {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    return next(
      new AppError('Authentication required', {
        statusCode: HTTP_STATUS.UNAUTHORIZED,
        errorCode: ERROR_CODES.UNAUTHORIZED,
      }),
    );
  }

  const token = header.slice(7);
  try {
    const authService = container.get('authService');
    req.user = authService.verifyAccessToken(token);
    return next();
  } catch (err) {
    return next(err);
  }
}

function optionalAuthMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header) {
    req.user = null;
    return next();
  }
  return authMiddleware(req, res, next);
}

module.exports = {
  authMiddleware,
  optionalAuthMiddleware,
};
