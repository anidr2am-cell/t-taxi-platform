const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function defaultKeyFn(req) {
  return `${req.ip}:${req.method}:${req.baseUrl}${req.route?.path ?? req.path}`;
}

function purgeExpiredBuckets(buckets, now) {
  for (const [key, bucket] of buckets.entries()) {
    if (bucket.resetAt <= now) {
      buckets.delete(key);
    }
  }
}

function createRateLimit({
  windowMs = 60_000,
  max = 20,
  keyFn = defaultKeyFn,
  nowFn = () => Date.now(),
  buckets = new Map(),
} = {}) {
  return (req, res, next) => {
    const now = nowFn();
    purgeExpiredBuckets(buckets, now);

    const key = keyFn(req);
    const bucket = buckets.get(key);

    if (!bucket || bucket.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }

    bucket.count += 1;
    if (bucket.count > max) {
      const retryAfterSeconds = Math.max(1, Math.ceil((bucket.resetAt - now) / 1000));
      res.set('Retry-After', String(retryAfterSeconds));
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
module.exports.defaultKeyFn = defaultKeyFn;
module.exports.purgeExpiredBuckets = purgeExpiredBuckets;
