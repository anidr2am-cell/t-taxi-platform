const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const {
  computeBookingCreateRequestHash,
  computeIdempotencyExpiresAt,
} = require('../utils/bookingIdempotency.util');

const MYSQL_DUP_ENTRY = 'ER_DUP_ENTRY';

function extractReplaySecrets(rawValue) {
  if (!rawValue) {
    return {};
  }
  const payload = typeof rawValue === 'object' ? rawValue : JSON.parse(rawValue);
  if (payload.bookingId !== undefined) {
    return {
      guestAccessToken: payload.guestAccessToken ?? null,
      boardingQrToken: payload.boardingQrToken ?? null,
    };
  }
  return {
    guestAccessToken: payload.guestAccessToken ?? null,
    boardingQrToken: payload.boardingQrToken ?? null,
  };
}

class BookingIdempotencyService {
  constructor(bookingIdempotencyRepository) {
    this.bookingIdempotencyRepository = bookingIdempotencyRepository;
  }

  computeRequestHash(input) {
    return computeBookingCreateRequestHash(input);
  }

  buildReplaySecrets({ guestAccessToken = null, boardingQrToken = null } = {}) {
    return {
      guestAccessToken,
      boardingQrToken,
    };
  }

  async begin(conn, idempotencyKey, requestHash) {
    const existing = await this.bookingIdempotencyRepository.findByKeyForUpdate(
      conn,
      idempotencyKey,
    );
    if (existing) {
      return this.resolveExistingRecord(existing, requestHash);
    }

    try {
      await this.bookingIdempotencyRepository.insertPending(conn, {
        idempotencyKey,
        requestHash,
        expiresAt: computeIdempotencyExpiresAt(),
      });
      return { action: 'proceed' };
    } catch (err) {
      if (err?.code !== MYSQL_DUP_ENTRY) {
        throw err;
      }
      const raced = await this.bookingIdempotencyRepository.findByKeyForUpdate(
        conn,
        idempotencyKey,
      );
      if (!raced) {
        throw err;
      }
      return this.resolveExistingRecord(raced, requestHash);
    }
  }

  resolveExistingRecord(existing, requestHash) {
    if (existing.request_hash !== requestHash) {
      throw new AppError('Idempotency key was already used with a different request payload', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.IDEMPOTENCY_KEY_REUSED,
      });
    }
    if (existing.status === 'COMPLETED') {
      return {
        action: 'replay',
        bookingId: existing.booking_id,
        replaySecrets: extractReplaySecrets(existing.response_payload),
        responseStatus: existing.response_status,
      };
    }
    throw new AppError('Booking creation is already in progress for this idempotency key', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.IDEMPOTENCY_REQUEST_IN_PROGRESS,
    });
  }

  async complete(conn, { idempotencyKey, bookingId, responseStatus, responsePayload }) {
    await this.bookingIdempotencyRepository.markCompleted(conn, {
      idempotencyKey,
      bookingId,
      responseStatus,
      responsePayload,
    });
  }

  async releasePending(conn, idempotencyKey) {
    await this.bookingIdempotencyRepository.deletePending(conn, idempotencyKey);
  }
}

module.exports = BookingIdempotencyService;
