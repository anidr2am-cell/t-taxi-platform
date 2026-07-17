const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');

class DriverTripFlowService {
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

  assertExpectedStatus(row, expectedStatus, toStatus) {
    if (!expectedStatus || row.status === expectedStatus) {
      return;
    }
    throw new AppError(
      `Invalid booking status transition from ${row.status} to ${toStatus}`,
      {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        errors: [{
          fromStatus: row.status,
          expectedStatus,
          toStatus,
          actorRole: ROLES.DRIVER,
        }],
      },
    );
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

  async runTransition(driverUserId, bookingNumber, toStatus, reason, options = {}) {
    const conn = await this.pool.getConnection();
    let transition;
    let normalizedBookingNumber;

    try {
      await conn.beginTransaction();
      const row = await this.loadActiveBookingForUpdate(conn, driverUserId, bookingNumber);
      normalizedBookingNumber = row.booking_number;
      this.assertExpectedStatus(row, options.expectedFromStatus, toStatus);
      transition = await this.transitionInTransaction(
        conn,
        normalizedBookingNumber,
        toStatus,
        this.actor(driverUserId),
        reason,
      );
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    await this.bookingStatusService.dispatchOutboxAfterCommit(transition.outboxId);
    this.bookingStatusService.emitDomainEvent(
      transition.domainEvent,
      transition.eventPayload,
    );

    if (
      toStatus === BOOKING_STATUS.COMPLETED
      || toStatus === BOOKING_STATUS.CANCELLED
      || toStatus === BOOKING_STATUS.NO_SHOW
      || toStatus === BOOKING_STATUS.SETTLEMENT_PENDING
    ) {
      return {
        bookingNumber: normalizedBookingNumber,
        status: toStatus,
        idempotent: transition.result.idempotent,
      };
    }

    return this.getUpdatedDetail(driverUserId, normalizedBookingNumber, {
      idempotent: transition.result.idempotent,
    });
  }

  startOnRoute(driverUserId, bookingNumber) {
    return this.runTransition(
      driverUserId,
      bookingNumber,
      BOOKING_STATUS.ON_ROUTE,
      'DRIVER_START_ON_ROUTE',
      { expectedFromStatus: BOOKING_STATUS.DRIVER_ASSIGNED },
    );
  }

  markArrived(driverUserId, bookingNumber) {
    return this.runTransition(
      driverUserId,
      bookingNumber,
      BOOKING_STATUS.DRIVER_ARRIVED,
      'DRIVER_MARK_ARRIVED',
      { expectedFromStatus: BOOKING_STATUS.ON_ROUTE },
    );
  }

  markPickedUp(driverUserId, bookingNumber) {
    return this.runTransition(
      driverUserId,
      bookingNumber,
      BOOKING_STATUS.PICKED_UP,
      'DRIVER_MARK_PICKED_UP',
      { expectedFromStatus: BOOKING_STATUS.DRIVER_ARRIVED },
    );
  }

  endTrip(driverUserId, bookingNumber) {
    return this.runTransition(
      driverUserId,
      bookingNumber,
      BOOKING_STATUS.SETTLEMENT_PENDING,
      'DRIVER_END_TRIP',
      { expectedFromStatus: BOOKING_STATUS.PICKED_UP },
    );
  }

  completeTrip(driverUserId, bookingNumber) {
    return this.endTrip(driverUserId, bookingNumber);
  }
}

module.exports = DriverTripFlowService;
