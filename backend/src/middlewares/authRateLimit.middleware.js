const createRateLimit = require('./rateLimit.middleware');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;
const ONE_MINUTE_MS = 60 * 1000;

function normalizeLoginIdentifier(body = {}) {
  const email = String(body.email ?? '').trim().toLowerCase();
  if (email) return `email:${email}`;
  const phone = String(body.phone ?? '').trim();
  if (phone) return `phone:${phone}`;
  return null;
}

const loginIpRateLimit = createRateLimit({
  windowMs: FIFTEEN_MINUTES_MS,
  max: 10,
  keyFn: (req) => `auth:login:ip:${req.ip}`,
});

const loginIdentifierRateLimit = createRateLimit({
  windowMs: FIFTEEN_MINUTES_MS,
  max: 10,
  keyFn: (req) => {
    const identifier = normalizeLoginIdentifier(req.body);
    if (identifier) {
      return `auth:login:id:${identifier}`;
    }
    return `auth:login:id:missing:${req.ip}`;
  },
});

const registerRateLimit = createRateLimit({
  windowMs: ONE_HOUR_MS,
  max: 5,
  keyFn: (req) => `auth:register:ip:${req.ip}`,
});

const refreshRateLimit = createRateLimit({
  windowMs: ONE_MINUTE_MS,
  max: 120,
  keyFn: (req) => `auth:refresh:ip:${req.ip}`,
});

module.exports = {
  loginIpRateLimit,
  loginIdentifierRateLimit,
  registerRateLimit,
  refreshRateLimit,
  normalizeLoginIdentifier,
};
