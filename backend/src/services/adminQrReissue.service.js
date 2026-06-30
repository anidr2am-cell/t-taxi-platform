const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const config = require('../config/env');
const { generateSecureToken, hashToken } = require('../utils/tokenHash.util');

const BOARDING_QR_TTL_HOURS = 48;
const DROPOFF_QR_TTL_HOURS = 48;

const TERMINAL_STATUSES = new Set([
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.NO_SHOW,
]);

const BOARDING_REISSUE_STATUSES = new Set([
  BOOKING_STATUS.PENDING,
  BOOKING_STATUS.CONFIRMED,
  BOOKING_STATUS.DRIVER_ASSIGNED,
  BOOKING_STATUS.DRIVER_ARRIVED,
]);

class AdminQrReissueService {
  constructor(pool, bookingRepository, options = {}) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.allowDevQrReissue = options.allowDevQrReissue ?? config.features.allowDevQrReissue;
    this.nodeEnv = options.nodeEnv ?? config.server.nodeEnv;
  }

  isEnabled() {
    return this.allowDevQrReissue && this.nodeEnv !== 'production';
  }

  addHours(date, hours) {
    const result = new Date(date);
    result.setHours(result.getHours() + hours);
    return result;
  }

  addDays(date, days) {
    const result = new Date(date);
    result.setDate(result.getDate() + days);
    return result;
  }

  formatDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  assertEnabled() {
    if (!this.isEnabled()) {
      throw new AppError('QR reissue is not available in this environment', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.FORBIDDEN,
      });
    }
  }

  canReissueBoarding(booking) {
    if (!this.isEnabled()) return false;
    if (TERMINAL_STATUSES.has(booking.status)) return false;
    if (booking.boarding_qr_used_at) return false;
    return BOARDING_REISSUE_STATUSES.has(booking.status);
  }

  canReissueDropoff(booking) {
    if (!this.isEnabled()) return false;
    if (booking.status !== BOOKING_STATUS.PICKED_UP) return false;
    if (booking.dropoff_qr_used_at) return false;
    return true;
  }

  disabledReason() {
    if (this.nodeEnv === 'production') {
      return 'QR reissue is disabled in production';
    }
    if (!this.allowDevQrReissue) {
      return 'Set ALLOW_DEV_QR_REISSUE=true on the backend and restart';
    }
    return null;
  }

  boardingUnavailableReason(booking) {
    if (TERMINAL_STATUSES.has(booking.status)) {
      return 'Booking is in a terminal status';
    }
    if (booking.boarding_qr_used_at) {
      return 'Boarding QR already used';
    }
    if (!BOARDING_REISSUE_STATUSES.has(booking.status)) {
      return `Boarding QR reissue is not available in status ${booking.status}`;
    }
    return null;
  }

  dropoffUnavailableReason(booking) {
    if (booking.status !== BOOKING_STATUS.PICKED_UP) {
      return `Dropoff QR reissue requires status ${BOOKING_STATUS.PICKED_UP}`;
    }
    if (booking.dropoff_qr_used_at) {
      return 'Dropoff QR already used';
    }
    return null;
  }

  buildDevTools(booking) {
    const enabled = this.isEnabled();
    return {
      qrReissueEnabled: enabled,
      disabledReason: enabled ? null : this.disabledReason(),
      boarding: {
        reissueAvailable: this.canReissueBoarding(booking),
        consumed: Boolean(booking.boarding_qr_used_at),
        previouslyIssued: Boolean(booking.boarding_qr_token_hash),
        unavailableReason: enabled && !this.canReissueBoarding(booking)
          ? this.boardingUnavailableReason(booking)
          : null,
      },
      dropoff: {
        reissueAvailable: this.canReissueDropoff(booking),
        consumed: Boolean(booking.dropoff_qr_used_at),
        previouslyIssued: Boolean(booking.dropoff_qr_token_hash),
        unavailableReason: enabled && !this.canReissueDropoff(booking)
          ? this.dropoffUnavailableReason(booking)
          : null,
      },
    };
  }

  resolveBoardingExpiry(booking) {
    if (booking.scheduled_pickup_at) {
      return this.formatDateTime(
        this.addHours(new Date(booking.scheduled_pickup_at), BOARDING_QR_TTL_HOURS),
      );
    }
    return this.formatDateTime(this.addDays(new Date(), 30));
  }

  async reissueQr(bookingNumber, type, user) {
    this.assertEnabled();

    const normalizedType = String(type ?? '').trim().toUpperCase();
    if (normalizedType !== 'BOARDING' && normalizedType !== 'DROPOFF') {
      throw new AppError('Invalid QR type', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const rawToken = generateSecureToken();
    const conn = await this.pool.getConnection();
    let booking;
    let expiresAt;

    try {
      await conn.beginTransaction();

      booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );

      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      if (normalizedType === 'BOARDING') {
        if (!this.canReissueBoarding(booking)) {
          throw new AppError('Boarding QR cannot be reissued for this booking', {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
          });
        }
        expiresAt = this.resolveBoardingExpiry(booking);
        await this.bookingRepository.setBoardingQr(
          conn,
          booking.id,
          hashToken(rawToken),
          expiresAt,
        );
      } else {
        if (!this.canReissueDropoff(booking)) {
          throw new AppError('Dropoff QR cannot be reissued for this booking', {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
          });
        }
        expiresAt = this.formatDateTime(this.addHours(new Date(), DROPOFF_QR_TTL_HOURS));
        await this.bookingRepository.setDropoffQr(
          conn,
          booking.id,
          hashToken(rawToken),
          expiresAt,
        );
      }

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'QR_TOKEN_REISSUED',
        actorUserId: user.id,
        actorRole: user.role,
        description: `${normalizedType} QR token reissued for development testing`,
        payload: {
          qrType: normalizedType,
          expiresAt,
          previousHashInvalidated: true,
        },
      });

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    const response = {
      bookingNumber: booking.booking_number,
      qrType: normalizedType,
      expiresAt,
    };

    if (normalizedType === 'BOARDING') {
      response.boardingQrToken = rawToken;
    } else {
      response.dropoffQrToken = rawToken;
    }

    return response;
  }
}

module.exports = AdminQrReissueService;
