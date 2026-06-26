/**
 * utils/AppError.js — Operational errors with error_code
 */
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

class AppError extends Error {
  constructor(message, {
    statusCode = HTTP_STATUS.BAD_REQUEST,
    errorCode = ERROR_CODES.VALIDATION_ERROR,
    errors = null,
    isOperational = true,
  } = {}) {
    super(message);
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.errors = errors;
    this.isOperational = isOperational;
    Error.captureStackTrace(this, this.constructor);
  }
}

module.exports = AppError;
