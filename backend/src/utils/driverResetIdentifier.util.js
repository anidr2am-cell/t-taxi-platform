function thaiMobileNumber(identifier) {
  const compact = identifier.replace(/[ ()-]/g, '');
  const match = /^(?:0|\+66|0066|66)([689][0-9]{8})$/.exec(compact);
  return match?.[1] ?? null;
}

function normalizeDriverResetIdentifier(identifier) {
  const value = String(identifier ?? '').trim().toLowerCase();
  const national = thaiMobileNumber(value);
  return national ? `+66${national}` : value;
}

module.exports = { thaiMobileNumber, normalizeDriverResetIdentifier };
