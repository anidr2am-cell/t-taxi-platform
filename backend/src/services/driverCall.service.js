const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const {
  emitDriverCallClaimed,
  emitDriverCallConfirmed,
} = require('../socket/realtime');

class DriverCallService {
  constructor(pool, bookingRepository, driverRepository, driverJobService) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.driverJobService = driverJobService;
  }

  validateBookingNumber(bookingNumber) {
    return this.driverJobService.validateBookingNumber(bookingNumber);
  }

  passengerCount(row) {
    return Number(row.adults || 0) + Number(row.children || 0) + Number(row.infants || 0);
  }

  mapOpenCall(row) {
    return {
      bookingNumber: row.booking_number,
      status: row.status,
      scheduledPickupAt: row.scheduled_pickup_at,
      pickupDate: row.pickup_date,
      pickupTime: row.pickup_time,
      origin: row.origin_address,
      destination: row.destination_address,
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      vehicleType: {
        code: row.vehicle_type_code,
        name: row.vehicle_type_name,
      },
      passengerCount: this.passengerCount(row),
      amount: Number(row.total_amount || 0),
      currency: row.currency,
      luggage: {
        carriers20Inch: Number(row.carriers_20_inch || 0),
        carriers24InchPlus: Number(row.carriers_24_inch_plus || 0),
        golfBags: Number(row.golf_bags || 0),
        specialItems: row.special_items ?? null,
      },
    };
  }

  async listOpenCalls(driverUserId) {
    const rows = await this.bookingRepository.findOpenDriverCallsForDriver(driverUserId);
    return {
      items: rows.map((row) => this.mapOpenCall(row)),
    };
  }

  throwAlreadyClaimed() {
    throw new AppError('Another driver has already claimed this booking', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.ALREADY_ASSIGNED,
    });
  }

  assertDriverCanClaim(driver) {
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    if (!driver.is_online || driver.status !== 'AVAILABLE') {
      throw new AppError('Driver must be online and available to claim calls', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_AVAILABLE,
      });
    }
  }

  async claimOpenCall(driverUserId, bookingNumber) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const conn = await this.pool.getConnection();
    let confirmedPayload = null;

    try {
      await conn.beginTransaction();

      const driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      this.assertDriverCanClaim(driver);

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        normalizedBookingNumber,
      );
      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }
      if (booking.status !== BOOKING_STATUS.OPEN) {
        this.throwAlreadyClaimed();
      }

      const active = await this.bookingRepository.findActiveAssignmentForUpdate(
        conn,
        booking.id,
      );
      if (active) {
        this.throwAlreadyClaimed();
      }

      const hasActiveJob = await this.driverRepository.hasActiveJob(conn, driver.id);
      if (hasActiveJob) {
        throw new AppError('Driver already has an active assignment', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_AVAILABLE,
        });
      }

      const vehicle = await this.driverRepository.findMatchingVehicle(
        conn,
        driver.id,
        booking.vehicle_type_id,
      );
      if (!vehicle) {
        throw new AppError('Driver vehicle type does not match booking', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
        });
      }

      const assignmentId = await this.bookingRepository.insertDriverAssignment(conn, {
        bookingId: booking.id,
        driverId: driver.id,
        driverVehicleId: vehicle.id,
        assignedByUserId: driver.user_id,
        assignmentReason: 'DRIVER_CLAIM_OPEN_CALL',
      });

      await this.bookingRepository.updateStatus(
        conn,
        booking.id,
        BOOKING_STATUS.DRIVER_ASSIGNED,
        driver.user_id,
      );
      await this.bookingRepository.insertStatusLog(conn, booking.id, {
        fromStatus: BOOKING_STATUS.OPEN,
        toStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
        changedByUserId: driver.user_id,
        changedByRole: ROLES.DRIVER,
        reason: 'DRIVER_CLAIMED_OPEN_CALL',
      });
      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'DRIVER_CLAIMED_OPEN_CALL',
        actorUserId: driver.user_id,
        actorRole: ROLES.DRIVER,
        description: `Driver ${driver.name} claimed open booking`,
        payload: {
          bookingNumber: normalizedBookingNumber,
          driverId: driver.id,
          assignmentId,
        },
      });

      await conn.commit();

      confirmedPayload = await this.driverJobService.getDetail(
        driverUserId,
        normalizedBookingNumber,
      );
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    emitDriverCallClaimed({ bookingNumber: normalizedBookingNumber });
    emitDriverCallConfirmed(driverUserId, {
      bookingNumber: normalizedBookingNumber,
      booking: confirmedPayload,
    });

    return {
      bookingNumber: normalizedBookingNumber,
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      booking: confirmedPayload,
    };
  }
}

module.exports = DriverCallService;
