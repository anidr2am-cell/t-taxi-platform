const GUEST_ACCESS_TOKEN_HEADER = 'x-guest-access-token';

/**
 * Guest booking access token from request header (never URL/query).
 */
function extractGuestAccessTokenFromHeader(req) {
  const value = req.headers[GUEST_ACCESS_TOKEN_HEADER];
  if (value == null || value === '') return null;
  return String(value).trim();
}

module.exports = {
  GUEST_ACCESS_TOKEN_HEADER,
  extractGuestAccessTokenFromHeader,
};
