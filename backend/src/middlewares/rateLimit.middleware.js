const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function createRateLimit({ windowMs = 60_000, max = 20 } = {}) {
  const buckets = new Map();

  return (req, _res, next) => {
    const now = Date.now();
    const key = `${req.ip}:${req.method}:${req.baseUrl}${req.route?.path ?? req.path}`;
    const bucket = buckets.get(key);

    if (!bucket || bucket.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }

    bucket.count += 1;
    if (bucket.count > max) {
      return next(
        new AppError('Too many requests', {
          statusCode: HTTP_STATUS.TOO_MANY_REQUESTS,
          errorCode: ERROR_CODES.RATE_LIMIT,
        }),
      );
    }

    return next();
  };
}

module.exports = createRateLimit;
