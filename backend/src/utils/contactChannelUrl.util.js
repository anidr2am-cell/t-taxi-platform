const BLOCKED_SCHEMES = new Set(['javascript', 'data', 'file', 'vbscript']);

const ALLOWED_SCHEMES = new Set([
  'https',
  'http',
  'line',
  'kakaotalk',
  'whatsapp',
]);

function normalizeScheme(value) {
  return String(value ?? '').trim().toLowerCase().replace(/:$/, '');
}

function extractScheme(rawUrl) {
  const trimmed = String(rawUrl ?? '').trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/);
  return match ? normalizeScheme(match[1]) : null;
}

function validateContactChannelUrl(rawUrl, options = {}) {
  const allowHttp = options.allowHttp ?? process.env.NODE_ENV !== 'production';
  const trimmed = String(rawUrl ?? '').trim();
  if (!trimmed) {
    return { valid: false, reason: 'empty' };
  }

  const scheme = extractScheme(trimmed);
  if (!scheme) {
    return { valid: false, reason: 'malformed' };
  }
  if (BLOCKED_SCHEMES.has(scheme)) {
    return { valid: false, reason: 'blocked_scheme' };
  }
  if (!ALLOWED_SCHEMES.has(scheme)) {
    return { valid: false, reason: 'unsupported_scheme' };
  }
  if (scheme === 'http' && !allowHttp) {
    return { valid: false, reason: 'http_not_allowed' };
  }

  if (scheme === 'https' || scheme === 'http') {
    try {
      const parsed = new URL(trimmed);
      if (normalizeScheme(parsed.protocol) !== scheme) {
        return { valid: false, reason: 'malformed' };
      }
    } catch (_) {
      return { valid: false, reason: 'malformed' };
    }
  }

  return { valid: true, scheme };
}

module.exports = {
  ALLOWED_SCHEMES,
  BLOCKED_SCHEMES,
  validateContactChannelUrl,
};
