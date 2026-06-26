function parseExpiresInToSeconds(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  const str = String(value || '').trim();
  const match = /^(\d+)([smhd])$/i.exec(str);
  if (!match) {
    return 3600;
  }

  const amount = Number.parseInt(match[1], 10);
  const unit = match[2].toLowerCase();
  const multipliers = { s: 1, m: 60, h: 3600, d: 86400 };
  return amount * multipliers[unit];
}

module.exports = {
  parseExpiresInToSeconds,
};
