const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const { hashToken } = require('../utils/tokenHash.util');

// Legacy QR scan service — kept for API/DB compatibility; driver button flow must not use this.
class DriverQrService {
  constructor(pool, bookingRepository, bookingStatusService, driverJobService) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.bookingStatusService = bookingStatusService;
    this.driverJobService = driverJobService;
  }

  actor(driverUserId) {
    return { id: driverUserId, role: ROLES.DRIVER };
  }

  notFound() {
    return new AppError('Booking not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
    });
  }

  qrError(message, errorCode, statusCode = HTTP_STATUS.BAD_REQUEST) {
    return new AppError(message, { statusCode, errorCode });
  }

  validateToken(token) {
    const value = String(token ?? '').trim();
    if (!value) {
      throw this.qrError('Invalid QR token', ERROR_CODES.INVALID_QR_TOKEN);
    }
    return value;
  }

  isExpired(value, now = new Date()) {
    if (!value) return true;
    return new Date(value).getTime() <= now.getTime();
  }

  async loadActiveBookingForUpdate(conn, driverUserId, bookingNumber) {
    const normalizedBookingNumber = this.driverJobService.validateBookingNumber(bookingNumber);
    const row = await this.bookingRepository.findActiveDriverBookingByNumberForUpdate(
      conn,
      driverUserId,
      normalizedBookingNumber,
    );
    if (!row) {
      throw this.notFound();
    }
    return row;
  }

  async verifyTokenIdentity(conn, row, tokenHash, purpose) {
    const expectedField = purpose === 'BOARDING'
      ? 'boarding_qr_token_hash'
      : 'dropoff_qr_token_hash';
    const otherField = purpose === 'BOARDING'
      ? 'dropoff_qr_token_hash'
      : 'boarding_qr_token_hash';

    if (row[expectedField] === tokenHash) {
      return;
    }

    if (row[otherField] === tokenHash) {
      throw this.qrError(
        'QR token type does not match this operation',
        ERROR_CODES.QR_TOKEN_TYPE_MISMATCH,
        HTTP_STATUS.CONFLICT,
      );
    }

    const owner = await this.bookingRepository.findQrTokenBooking(conn, tokenHash);
    if (owner?.id && owner.id !== row.id) {
      throw this.qrError(
        'QR token belongs to a different booking',
        ERROR_CODES.QR_TOKEN_BOOKING_MISMATCH,
        HTTP_STATUS.CONFLICT,
      );
    }

    if (owner?.token_type && owner.token_type !== purpose) {
      throw this.qrError(
        'QR token type does not match this operation',
        ERROR_CODES.QR_TOKEN_TYPE_MISMATCH,
        HTTP_STATUS.CONFLICT,
      );
    }

    throw this.qrError('Invalid QR token', ERROR_CODES.INVALID_QR_TOKEN);
  }

  async transitionInTransaction(conn, bookingNumber, status, actor, reason) {
    return this.bookingStatusService.transitionInTransaction(
      conn,
      bookingNumber,
      { status, reason },
      actor,
      { skipAccessCheck: true },
    );
  }

  async getUpdatedDetail(driverUserId, bookingNumber, extra = {}) {
    const detail = await this.driverJobService.getDetail(driverUserId, bookingNumber);
    return { ...detail, ...extra };
  }

  async scanBoarding(driverUserId, bookingNumber, token) {
    const value = this.validateToken(token);
    const tokenHash = hashToken(value);
    const conn = await this.pool.getConnection();
    let transition;
    let normalizedBookingNumber;
    let idempotent = false;

    try {
      await conn.beginTransaction();
      const row = await this.loadActiveBookingForUpdate(conn, driverUserId, bookingNumber);
      normalizedBookingNumber = row.booking_number;
      await this.verifyTokenIdentity(conn, row, tokenHash, 'BOARDING');

      if (row.boarding_qr_used_at && row.status === BOOKING_STATUS.PICKED_UP) {
        idempotent = true;
        await conn.commit();
      } else {
        if (row.boarding_qr_used_at) {
          throw this.qrError(
            'QR token has already been used',
            ERROR_CODES.QR_TOKEN_ALREADY_USED,
            HTTP_STATUS.CONFLICT,
          );
        }
        if (this.isExpired(row.boarding_qr_expires_at)) {
          throw this.qrError('QR token has expired', ERROR_CODES.QR_TOKEN_EXPIRED);
        }
        if (row.status !== BOOKING_STATUS.DRIVER_ARRIVED) {
          this.bookingStatusService.validateTransition(
            row.status,
            BOOKING_STATUS.PICKED_UP,
            ROLES.DRIVER,
          );
        }

        const consumed = await this.bookingRepository.markBoardingQrUsed(conn, row.id);
        if (!consumed) {
          throw this.qrError(
            'QR token has already been used',
            ERROR_CODES.QR_TOKEN_ALREADY_USED,
            HTTP_STATUS.CONFLICT,
          );
        }

        transition = await this.transitionInTransaction(
          conn,
          normalizedBookingNumber,
          BOOKING_STATUS.PICKED_UP,
          this.actor(driverUserId),
          'DRIVER_SCAN_BOARDING_QR',
        );
        await conn.commit();
      }
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    if (transition) {
      await this.bookingStatusService.dispatchOutboxAfterCommit(transition.outboxId);
    this.bookingStatusService.emitDomainEvent(
        transition.domainEvent,
        transition.eventPayload,
      );
    }

    return this.getUpdatedDetail(driverUserId, normalizedBookingNumber, {
      idempotent: idempotent || Boolean(transition?.result.idempotent),
      dropoffQrEligible: true,
    });
  }

  async scanDropoff(driverUserId, bookingNumber, token) {
    const value = this.validateToken(token);
    const tokenHash = hashToken(value);
    const conn = await this.pool.getConnection();
    let transition;
    let normalizedBookingNumber;
    let idempotent = false;

    try {
      await conn.beginTransaction();
      const row = await this.loadActiveBookingForUpdate(conn, driverUserId, bookingNumber);
      normalizedBookingNumber = row.booking_number;
      await this.verifyTokenIdentity(conn, row, tokenHash, 'DROPOFF');

      if (row.dropoff_qr_used_at && row.status === BOOKING_STATUS.SETTLEMENT_PENDING) {
        idempotent = true;
        await conn.commit();
      } else {
        if (row.dropoff_qr_used_at) {
          throw this.qrError(
            'QR token has already been used',
            ERROR_CODES.QR_TOKEN_ALREADY_USED,
            HTTP_STATUS.CONFLICT,
          );
        }
        if (this.isExpired(row.dropoff_qr_expires_at)) {
          throw this.qrError('QR token has expired', ERROR_CODES.QR_TOKEN_EXPIRED);
        }
        if (row.status !== BOOKING_STATUS.PICKED_UP) {
          this.bookingStatusService.validateTransition(
            row.status,
            BOOKING_STATUS.SETTLEMENT_PENDING,
            ROLES.DRIVER,
          );
        }

        const consumed = await this.bookingRepository.markDropoffQrUsed(conn, row.id);
        if (!consumed) {
          throw this.qrError(
            'QR token has already been used',
            ERROR_CODES.QR_TOKEN_ALREADY_USED,
            HTTP_STATUS.CONFLICT,
          );
        }

        transition = await this.transitionInTransaction(
          conn,
          normalizedBookingNumber,
          BOOKING_STATUS.SETTLEMENT_PENDING,
          this.actor(driverUserId),
          'DRIVER_SCAN_DROPOFF_QR',
        );
        await conn.commit();
      }
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    if (transition) {
      await this.bookingStatusService.dispatchOutboxAfterCommit(transition.outboxId);
    this.bookingStatusService.emitDomainEvent(
        transition.domainEvent,
        transition.eventPayload,
      );
    }

    return this.getUpdatedDetail(driverUserId, normalizedBookingNumber, {
      idempotent: idempotent || Boolean(transition?.result.idempotent),
    });
  }
}

module.exports = DriverQrService;
