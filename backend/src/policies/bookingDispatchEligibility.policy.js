const CONTACT_STATUS = require('../constants/contactStatus');
const config = require('../config/env');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

function isContactConnectionRequired() {
  return config.features?.contactConnectionRequired === true;
}

function isBookingContactVerified(booking) {
  if (!isContactConnectionRequired()) {
    return true;
  }
  const status = booking?.contact_status ?? booking?.contactStatus ?? CONTACT_STATUS.VERIFIED;
  return status === CONTACT_STATUS.VERIFIED;
}

function assertBookingDispatchEligible(booking) {
  if (isBookingContactVerified(booking)) {
    return;
  }
  throw new AppError('Booking contact is not verified for dispatch', {
    statusCode: HTTP_STATUS.CONFLICT,
    errorCode: ERROR_CODES.BOOKING_CONTACT_NOT_VERIFIED,
  });
}

module.exports = {
  isContactConnectionRequired,
  isBookingContactVerified,
  assertBookingDispatchEligible,
};
