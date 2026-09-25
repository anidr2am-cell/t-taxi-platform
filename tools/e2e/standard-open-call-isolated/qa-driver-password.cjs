'use strict';

const fs = require('node:fs');

/**
 * QA driver login password — never commit a value. Set at runtime:
 * - QA_DRIVER_PASSWORD (process env, server session only), or
 * - QA_DRIVER_PASSWORD_FILE (path to mode-600 file, one line).
 */
function qaPasswordMissingError(detail) {
  const err = new Error(detail);
  err.code = 'QA_PASSWORD_MISSING';
  return err;
}

function resolveQaDriverPassword() {
  const direct = process.env.QA_DRIVER_PASSWORD;
  if (direct && String(direct).trim()) {
    return String(direct).trim();
  }
  const filePath = process.env.QA_DRIVER_PASSWORD_FILE;
  if (filePath) {
    let text;
    try {
      text = fs.readFileSync(filePath, 'utf8').trim();
    } catch {
      throw qaPasswordMissingError('QA_DRIVER_PASSWORD_FILE unreadable');
    }
    if (!text) {
      throw qaPasswordMissingError('QA_DRIVER_PASSWORD_FILE is empty');
    }
    return text;
  }
  throw qaPasswordMissingError(
    'Missing QA driver password: set QA_DRIVER_PASSWORD or QA_DRIVER_PASSWORD_FILE',
  );
}

module.exports = { resolveQaDriverPassword };
