const createRateLimit = require('./rateLimit.middleware');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const customerBookingClaimIpRateLimit = createRateLimit({
  windowMs: FIFTEEN_MINUTES_MS,
  max: 30,
  keyFn: (req) => `customer:booking-claim:ip:${req.ip}`,
});

const customerBookingClaimUserRateLimit = createRateLimit({
  windowMs: FIFTEEN_MINUTES_MS,
  max: 20,
  keyFn: (req) => `customer:booking-claim:user:${req.user?.id ?? req.ip}`,
});

module.exports = {
  customerBookingClaimIpRateLimit,
  customerBookingClaimUserRateLimit,
};
