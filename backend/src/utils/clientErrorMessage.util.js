const HTTP_STATUS = require('../constants/httpStatus');

const MYSQL_ERROR_PREFIX = 'ER_';

const INTERNAL_MESSAGE_PATTERNS = [
  /data truncated/i,
  /incorrect .* value/i,
  /column\s+'/i,
  /table\s+'/i,
  /\bsql\b/i,
  /syntax error/i,
  /deadlock/i,
  /lock wait timeout/i,
];

const TRIP_END_FAILURE_MESSAGE =
  'We could not complete the trip. Please try again or contact an administrator.';

const GENERIC_INTERNAL_MESSAGE =
  'An unexpected error occurred. Please try again later.';

function isDatabaseOrInternalError(err) {
  if (!err || err.isOperational === true) {
    return false;
  }

  const code = String(err.code || '');
  if (code.startsWith(MYSQL_ERROR_PREFIX)) {
    return true;
  }

  const message = String(err.message || '');
  return INTERNAL_MESSAGE_PATTERNS.some((pattern) => pattern.test(message));
}

function resolveClientErrorMessage(err, options = {}) {
  if (err?.isOperational === true) {
    return err.message || GENERIC_INTERNAL_MESSAGE;
  }

  if (isDatabaseOrInternalError(err)) {
    return options.tripEndFailure ? TRIP_END_FAILURE_MESSAGE : GENERIC_INTERNAL_MESSAGE;
  }

  if (err?.message) {
    return err.message;
  }

  return GENERIC_INTERNAL_MESSAGE;
}

function isTripEndRequest(req) {
  const path = String(req?.path || req?.originalUrl || '');
  return /\/end-trip(?:\?|$)/i.test(path);
}

function resolveStatusCode(err) {
  if (err?.statusCode) {
    return err.statusCode;
  }

  if (err?.isOperational === true) {
    return HTTP_STATUS.BAD_REQUEST;
  }

  return HTTP_STATUS.INTERNAL_SERVER_ERROR;
}

module.exports = {
  TRIP_END_FAILURE_MESSAGE,
  GENERIC_INTERNAL_MESSAGE,
  isDatabaseOrInternalError,
  resolveClientErrorMessage,
  isTripEndRequest,
  resolveStatusCode,
};
