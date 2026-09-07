const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function defaultKeyFn(req) {
  return `${req.ip}:${req.method}:${req.baseUrl}${req.route?.path ?? req.path}`;
}

function purgeExpiredBuckets(buckets, now) {
  for (const [key, bucket] of buckets.entries()) {
    const blocked = bucket.blockedUntil && bucket.blockedUntil > now;
    if (!blocked && bucket.resetAt <= now) {
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
  penaltyWindowMs = null,
} = {}) {
  return (req, res, next) => {
    const now = nowFn();
    purgeExpiredBuckets(buckets, now);

    const key = keyFn(req);
    const bucket = buckets.get(key);

    if (bucket?.blockedUntil && bucket.blockedUntil > now) {
      const retryAfterSeconds = Math.max(1, Math.ceil((bucket.blockedUntil - now) / 1000));
      res.set('Retry-After', String(retryAfterSeconds));
      return next(
        new AppError('Too many requests', {
          statusCode: HTTP_STATUS.TOO_MANY_REQUESTS,
          errorCode: ERROR_CODES.RATE_LIMIT,
        }),
      );
    }

    if (!bucket || bucket.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs, blockedUntil: null });
      return next();
    }

    bucket.count += 1;
    if (bucket.count > max) {
      if (penaltyWindowMs) {
        bucket.blockedUntil = now + penaltyWindowMs;
      }
      const retryMs = penaltyWindowMs ?? (bucket.resetAt - now);
      const retryAfterSeconds = Math.max(1, Math.ceil(retryMs / 1000));
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
