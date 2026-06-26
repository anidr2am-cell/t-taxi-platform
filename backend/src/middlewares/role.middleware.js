/**
 * middlewares/role.middleware.js — Role-based access control
 *
 * 사용: router.get('/admin', authMiddleware, roleMiddleware(['ADMIN']), ...)
 */
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function roleMiddleware(allowedRoles = []) {
  return (req, res, next) => {
    if (!req.user) {
      return next(
        new AppError('Authentication required', {
          statusCode: HTTP_STATUS.UNAUTHORIZED,
          errorCode: ERROR_CODES.UNAUTHORIZED,
        }),
      );
    }

    if (!allowedRoles.includes(req.user.role)) {
      return next(
        new AppError('Insufficient permissions', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.FORBIDDEN,
        }),
      );
    }

    next();
  };
}

module.exports = roleMiddleware;
