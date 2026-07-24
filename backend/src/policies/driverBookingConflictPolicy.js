const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const PICKUP_CONFLICT_WINDOW_MS = 3 * 60 * 60 * 1000;

function assertNoPickupTimeConflict(existingRows, targetPickupAt, { excludeBookingId = null } = {}) {
  if (!targetPickupAt) {
    throw new AppError('Pickup time is required to accept this job', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
    });
  }
  const targetMs = new Date(targetPickupAt).getTime();
  if (!Number.isFinite(targetMs)) {
    throw new AppError('Pickup time is required to accept this job', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
    });
  }

  for (const row of existingRows ?? []) {
    if (excludeBookingId != null && Number(row.id) === Number(excludeBookingId)) {
      continue;
    }
    if (!row.scheduled_pickup_at) {
      throw new AppError('Assigned job pickup time is missing', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
      });
    }
    const existingMs = new Date(row.scheduled_pickup_at).getTime();
    if (!Number.isFinite(existingMs)) {
      throw new AppError('Assigned job pickup time is missing', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
      });
    }
    const diff = Math.abs(existingMs - targetMs);
    if (diff < PICKUP_CONFLICT_WINDOW_MS) {
      throw new AppError('Another assigned job is too close to this pickup time', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
      });
    }
  }
}

module.exports = {
  PICKUP_CONFLICT_WINDOW_MS,
  assertNoPickupTimeConflict,
};
