const crypto = require('crypto');

function versionForPath(assetPath) {
  return crypto
    .createHash('sha256')
    .update(String(assetPath))
    .digest('hex')
    .slice(0, 12);
}

function settingsAssetUrl(kind, assetPath) {
  if (!assetPath) return null;
  return `/api/v1/settings/assets/${kind}?v=${versionForPath(assetPath)}`;
}

module.exports = { settingsAssetUrl };
