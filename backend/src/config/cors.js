/**
 * config/cors.js — CORS options for Express & Socket.IO
 */
const env = require('./env');

const DEV_LOCAL_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function parseAllowlist(raw) {
  if (!raw || raw === '*') return [];
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

function isLocalDevOrigin(origin) {
  return typeof origin === 'string' && DEV_LOCAL_ORIGIN.test(origin);
}

function isDevelopmentLike(nodeEnv) {
  return nodeEnv === 'development' || nodeEnv === 'test';
}

function buildCorsPolicy({ nodeEnv, corsOriginRaw }) {
  const allowlist = parseAllowlist(corsOriginRaw || 'http://localhost:8080');
  const devLike = isDevelopmentLike(nodeEnv);

  function isAllowedOrigin(origin) {
    if (!origin) return true;
    if (allowlist.includes(origin)) return true;
    if (devLike && isLocalDevOrigin(origin)) return true;
    return false;
  }

  function resolveOrigin(requestOrigin, callback) {
    if (!requestOrigin) {
      callback(null, true);
      return;
    }
    callback(null, isAllowedOrigin(requestOrigin) ? requestOrigin : false);
  }

  const options = {
    origin: resolveOrigin,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Guest-Access-Token'],
  };

  return {
    allowlist,
    devLike,
    isAllowedOrigin,
    resolveOrigin,
    options,
  };
}

const policy = buildCorsPolicy({
  nodeEnv: env.server.nodeEnv,
  corsOriginRaw: env.cors.origin,
});

module.exports = {
  DEV_LOCAL_ORIGIN,
  parseAllowlist,
  isLocalDevOrigin,
  buildCorsPolicy,
  allowlist: policy.allowlist,
  isAllowedOrigin: policy.isAllowedOrigin,
  resolveOrigin: policy.resolveOrigin,
  origin: policy.allowlist,
  options: policy.options,
};
