const express = require('express');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const router = express.Router();

router.all('*', (req, res, next) => {
  next(
    new AppError(
      'Legacy /api/v1/chat endpoints are deprecated. Use booking-scoped /api/v1/bookings/:bookingNumber/chat.',
      {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      },
    ),
  );
});

module.exports = router;
