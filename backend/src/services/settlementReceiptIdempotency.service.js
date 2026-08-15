const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const MYSQL_DUP_ENTRY = 'ER_DUP_ENTRY';

function parseResponsePayload(rawValue) {
  if (!rawValue) return {};
  if (typeof rawValue === 'object') return { ...rawValue };
  try {
    return JSON.parse(rawValue) ?? {};
  } catch {
    return {};
  }
}

class SettlementReceiptIdempotencyService {
  constructor(settlementReceiptIdempotencyRepository) {
    this.settlementReceiptIdempotencyRepository = settlementReceiptIdempotencyRepository;
  }

  async begin(conn, {
    bookingId,
    driverUserId,
    idempotencyKey,
    requestFingerprint,
    expiresAt,
  }) {
    const existing = await this.settlementReceiptIdempotencyRepository.findByScopeForUpdate(
      conn,
      { bookingId, driverUserId, idempotencyKey },
    );
    if (existing) {
      return this.resolveExistingRecord(existing, requestFingerprint);
    }

    try {
      await this.settlementReceiptIdempotencyRepository.insertPending(conn, {
        bookingId,
        driverUserId,
        idempotencyKey,
        requestFingerprint,
        expiresAt,
      });
      return { action: 'proceed' };
    } catch (err) {
      if (err?.code !== MYSQL_DUP_ENTRY) {
        throw err;
      }
      const raced = await this.settlementReceiptIdempotencyRepository.findByScopeForUpdate(
        conn,
        { bookingId, driverUserId, idempotencyKey },
      );
      if (!raced) {
        throw err;
      }
      return this.resolveExistingRecord(raced, requestFingerprint);
    }
  }

  resolveExistingRecord(existing, requestFingerprint) {
    if (existing.request_fingerprint !== requestFingerprint) {
      throw new AppError('Idempotency key was already used with a different receipt upload', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.IDEMPOTENCY_KEY_REUSED,
      });
    }
    if (existing.status === 'COMPLETED') {
      return {
        action: 'replay',
        receiptFileId: existing.receipt_file_id,
        responseStatus: existing.response_status,
        responsePayload: parseResponsePayload(existing.response_payload),
      };
    }
    throw new AppError('Receipt upload is already in progress for this idempotency key', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.IDEMPOTENCY_REQUEST_IN_PROGRESS,
    });
  }

  async complete(conn, params) {
    await this.settlementReceiptIdempotencyRepository.markCompleted(conn, params);
  }

  async releasePending(conn, params) {
    await this.settlementReceiptIdempotencyRepository.deletePending(conn, params);
  }
}

module.exports = SettlementReceiptIdempotencyService;
