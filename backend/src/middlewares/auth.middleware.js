/**
 * middlewares/auth.middleware.js — JWT verification (skeleton)
 *
 * 구현 단계에서 jsonwebtoken으로 payload 검증 후 req.user 설정
 *
 * req.user 예시: { id, email, role }
 */
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

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

  // TODO: verify JWT via auth.service + config.jwt
  // const token = header.slice(7);
  // req.user = await authService.verifyAccessToken(token);

  return next(
    new AppError('Auth middleware not implemented yet', {
      statusCode: HTTP_STATUS.UNAUTHORIZED,
      errorCode: ERROR_CODES.UNAUTHORIZED,
    }),
  );
}

/**
 * Optional auth — guest booking flows
 */
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
