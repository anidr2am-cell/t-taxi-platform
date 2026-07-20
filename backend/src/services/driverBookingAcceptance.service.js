const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const { parseServiceDateTimeToMs } = require('../utils/serviceDateTime.util');

const STANDBY_WINDOW_MS = 60 * 60 * 1000;

class DriverBookingAcceptanceService {
  constructor(pool, bookingRepository, driverRepository, driverJobService) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.driverJobService = driverJobService;
  }

  notFound() {
    return new AppError('Booking not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
    });
  }

  notAcceptable() {
    return new AppError('Booking is not acceptable', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.BOOKING_NOT_ACCEPTABLE,
    });
  }

  assertActiveDriver(driver) {
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      throw new AppError('Driver is inactive', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.DRIVER_INACTIVE,
      });
    }
  }

  acceptedAtIso(value) {
    const parsedMs = parseServiceDateTimeToMs(value);
    if (parsedMs != null) return new Date(parsedMs).toISOString();
    throw new Error('Accepted assignment is missing accepted_at');
  }

  assertWithinStandbyWindow(booking, now = new Date()) {
    const pickupMs = parseServiceDateTimeToMs(booking.scheduled_pickup_at);
    const nowMs = now instanceof Date ? now.getTime() : Number(now);
    if (pickupMs == null || !Number.isFinite(nowMs)) {
      throw this.notAcceptable();
    }
    if (nowMs < pickupMs - STANDBY_WINDOW_MS) {
      throw this.notAcceptable();
    }
  }

  response(booking, assignment, idempotent) {
    return {
      bookingNumber: booking.booking_number,
      bookingStatus: booking.status,
      assignmentStatus: assignment.status,
      acceptedAt: this.acceptedAtIso(assignment.accepted_at),
      idempotent,
    };
  }

  async acceptBooking(driverUserId, bookingNumber, now = new Date()) {
    const normalizedBookingNumber = this.driverJobService.validateBookingNumber(
      bookingNumber,
    );
    const conn = await this.pool.getConnection();

    try {
      await conn.beginTransaction();

      const driver = await this.driverRepository.findByUserIdForUpdate(
        conn,
        driverUserId,
      );
      this.assertActiveDriver(driver);

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        normalizedBookingNumber,
      );
      if (!booking) throw this.notFound();

      let assignment = await this.bookingRepository.findActiveAssignmentForUpdate(
        conn,
        booking.id,
      );
      if (!assignment || Number(assignment.driver_id) !== Number(driver.id)) {
        throw this.notFound();
      }

      if (booking.status !== BOOKING_STATUS.DRIVER_ASSIGNED) {
        throw this.notAcceptable();
      }

      if (assignment.status === 'ACCEPTED') {
        const result = this.response(booking, assignment, true);
        await conn.commit();
        return result;
      }
      if (assignment.status !== 'ASSIGNED') throw this.notAcceptable();

      this.assertWithinStandbyWindow(booking, now);

      assignment = await this.bookingRepository.acceptDriverAssignment(
        conn,
        assignment.id,
      );
      if (!assignment) {
        const current = await this.bookingRepository.findActiveAssignmentForUpdate(
          conn,
          booking.id,
        );
        if (
          current
          && Number(current.driver_id) === Number(driver.id)
          && current.status === 'ACCEPTED'
        ) {
          const result = this.response(booking, current, true);
          await conn.commit();
          return result;
        }
        throw this.notAcceptable();
      }

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'DRIVER_BOOKING_ACCEPTED',
        actorUserId: driver.user_id,
        actorRole: ROLES.DRIVER,
        description: 'Driver accepted assigned booking',
        payload: {
          bookingNumber: normalizedBookingNumber,
          assignmentId: assignment.id,
        },
      });

      const result = this.response(booking, assignment, false);
      await conn.commit();
      return result;
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = DriverBookingAcceptanceService;
