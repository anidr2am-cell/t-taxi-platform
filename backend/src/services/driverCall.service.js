const AppError = require('../utils/AppError');
const { randomUUID } = require('node:crypto');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const {
  emitDriverCallClaimed,
  emitDriverCallConfirmed,
  emitDriverCallAvailable,
  emitDriverAssignmentReleased,
} = require('../socket/realtime');
const NOTIFICATION_TYPES = require('../constants/notificationTypes');
const RECIPIENT_TYPES = require('../constants/notificationRecipientTypes');
const {
  assertNoPickupTimeConflict,
} = require('../policies/driverBookingConflictPolicy');
const {
  ASSIGNMENT_RELEASE_MARKER,
  evaluateDriverAssignmentRelease,
  RELEASE_BLOCKED_REASON,
} = require('../policies/driverAssignmentRelease.policy');

const RELEASE_BLOCK_MESSAGES = {
  [RELEASE_BLOCKED_REASON.NOT_ASSIGNED_DRIVER]:
    'Booking is not assigned to this driver',
  [RELEASE_BLOCKED_REASON.NO_ACTIVE_ASSIGNMENT]:
    'No active assignment to release',
  [RELEASE_BLOCKED_REASON.TRIP_ALREADY_STARTED]:
    'Booking can only be released before the trip starts',
  [RELEASE_BLOCKED_REASON.WITHIN_TWO_HOURS]:
    'Normal assignment release is blocked within 2 hours of pickup. Use an emergency reason if needed.',
  [RELEASE_BLOCKED_REASON.BOOKING_TERMINAL_STATUS]:
    'This booking can no longer be released',
  [RELEASE_BLOCKED_REASON.INVALID_PICKUP_TIME]:
    'Booking pickup time is invalid for assignment release',
  [RELEASE_BLOCKED_REASON.INVALID_REASON]:
    'A valid release reason is required',
  [RELEASE_BLOCKED_REASON.REASON_DETAIL_REQUIRED]:
    'Please provide details when selecting Other',
  [RELEASE_BLOCKED_REASON.CUSTOMER_REQUEST_NOT_ALLOWED]:
    'Customer cancellation must use the customer cancel flow',
};

class DriverCallService {
  constructor(
    pool,
    bookingRepository,
    driverRepository,
    driverJobService,
    notificationRepository = null,
    chatRepository = null,
    commissionSettlementService = null,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.driverJobService = driverJobService;
    this.notificationRepository = notificationRepository;
    this.chatRepository = chatRepository;
    this.commissionSettlementService = commissionSettlementService;
  }

  validateBookingNumber(bookingNumber) {
    return this.driverJobService.validateBookingNumber(bookingNumber);
  }

  passengerCount(row) {
    return Number(row.adults || 0) + Number(row.children || 0) + Number(row.infants || 0);
  }

  mapOpenCall(row) {
    const paymentSummary = this.driverJobService.paymentSummary
      ? this.driverJobService.paymentSummary(row)
      : {};
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
      ...paymentSummary,
      luggage: {
        carriers20Inch: Number(row.carriers_20_inch || 0),
        carriers24InchPlus: Number(row.carriers_24_inch_plus || 0),
        golfBags: Number(row.golf_bags || 0),
        specialItems: row.special_items ?? null,
      },
    };
  }

  async listOpenCalls(driverUserId) {
    if (this.commissionSettlementService) {
      const driver = await this.driverRepository.findByUserId(driverUserId);
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        throw new AppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }
      if (await this.commissionSettlementService.driverHasBlockingSettlement(driver.id)) {
        return {
          items: [],
          blockedReason: 'UNPAID_SETTLEMENT',
          message: 'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
        };
      }
    }
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

  throwReleaseNotAllowed(message = 'Booking release is not allowed', extras = {}) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.BOOKING_RELEASE_NOT_ALLOWED,
      errors: Object.keys(extras).length ? [extras] : undefined,
    });
  }

  assertReleaseAllowed(evaluation) {
    if (evaluation.releaseAssignmentAvailable) return evaluation;
    const reason = evaluation.assignmentReleaseBlockedReason;
    this.throwReleaseNotAllowed(
      RELEASE_BLOCK_MESSAGES[reason] || 'Booking release is not allowed',
      {
        reason,
        assignmentReleaseDeadline: evaluation.assignmentReleaseDeadline,
        reassignmentPriority: evaluation.reassignmentPriority,
        releaseAssignmentEmergencyOnly: evaluation.releaseAssignmentEmergencyOnly,
      },
    );
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

  async assertSettlementEligible(driver) {
    if (!this.commissionSettlementService) return;
    if (await this.commissionSettlementService.driverHasBlockingSettlement(driver.id)) {
      throw new AppError('This driver cannot receive a new job until the previous settlement is confirmed.', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
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
      await this.assertSettlementEligible(driver);

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

      const released = await this.bookingRepository.hasReleasedAssignment(
        conn,
        booking.id,
        driver.id,
      );
      if (released) {
        throw new AppError('Driver has already released this booking', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED,
        });
      }

      const conflictRows = await this.driverRepository.findActiveAssignmentPickupsForConflict(
        conn,
        driver.id,
      );
      assertNoPickupTimeConflict(conflictRows, booking.scheduled_pickup_at);

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

      const detailRow = await this.bookingRepository.findActiveDriverBookingByNumberForUpdate(
        conn,
        driverUserId,
        normalizedBookingNumber,
      );
      if (!detailRow) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }
      confirmedPayload = this.driverJobService.mapDetail(detailRow);

      await conn.commit();
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

  async notifyEligibleDriversForReopenedBooking(conn, {
    booking,
    openCallPayload,
    releasedAssignmentId,
  }) {
    const candidates = await this.driverRepository.listEligibleForOpenBooking(
      conn,
      booking.vehicle_type_id,
      { excludeReleasedBookingId: booking.id },
    );
    const drivers = [];
    for (const driver of candidates) {
      const blocked = this.commissionSettlementService
        ? await this.commissionSettlementService.driverHasBlockingSettlement(driver.id)
        : false;
      if (!blocked) drivers.push(driver);
    }

    const eventId = randomUUID();
    if (this.notificationRepository) {
      for (const driver of drivers) {
        await this.notificationRepository.insert(conn, {
          recipientType: RECIPIENT_TYPES.USER,
          userId: driver.user_id,
          recipientDriverId: driver.id,
          bookingId: booking.id,
          audienceRole: ROLES.DRIVER,
          eventId,
          eventName: 'driver.call.available',
          idempotencyKey: `driver-call-reopened:${booking.id}:${driver.id}:${releasedAssignmentId}`,
          notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
          title: '새 예약이 도착했습니다',
          body: `${openCallPayload.origin} → ${openCallPayload.destination}`,
          payload: openCallPayload,
        });
      }
    }

    return drivers.map((driver) => ({
      driverId: driver.id,
      userId: driver.user_id,
    }));
  }

  async deactivateReleasedDriverChatParticipant(conn, booking, driverUserId) {
    if (!this.chatRepository) return;
    const room = await this.chatRepository.findRoomByBookingIdForUpdate(
      conn,
      booking.id,
    );
    if (!room) return;
    await this.chatRepository.deactivateParticipant(
      conn,
      room.id,
      'DRIVER',
      driverUserId,
    );
  }

  async releaseAssignment(driverUserId, bookingNumber, input = {}, options = {}) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const conn = await this.pool.getConnection();
    let releasedDriverUserId = driverUserId;
    let openCallPayload = null;
    let openCallTargets = [];
    let releaseResult = null;
    const nowMs = options.nowMs ?? Date.now();

    try {
      await conn.beginTransaction();

      const driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        throw new AppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }

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

      const active = await this.bookingRepository.findActiveAssignmentForUpdate(
        conn,
        booking.id,
      );
      if (!active) {
        const released = await this.bookingRepository.hasReleasedAssignment(
          conn,
          booking.id,
          driver.id,
        );
        throw new AppError(
          released ? 'Assignment already released' : 'Booking is not assigned to this driver',
          {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: released
              ? ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED
              : ERROR_CODES.BOOKING_NOT_ASSIGNED_TO_DRIVER,
          },
        );
      }

      if (Number(active.driver_id) !== Number(driver.id)) {
        throw new AppError('Booking is not assigned to this driver', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.BOOKING_NOT_ASSIGNED_TO_DRIVER,
        });
      }

      const evaluation = evaluateDriverAssignmentRelease({
        bookingStatus: booking.status,
        scheduledPickupAt: booking.scheduled_pickup_at,
        hasActiveAssignment: true,
        isAssignedDriver: true,
        reasonCode: input.reasonCode == null ? '' : input.reasonCode,
        reasonDetail: input.reasonDetail,
        nowMs,
      });
      this.assertReleaseAllowed(evaluation);

      const deactivated = await this.bookingRepository.deactivateAssignment(
        conn,
        active.id,
        ASSIGNMENT_RELEASE_MARKER,
      );
      if (!deactivated) {
        throw new AppError('Assignment already released', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED,
        });
      }

      await this.bookingRepository.reopenAfterDriverRelease(
        conn,
        booking.id,
        driver.user_id,
      );
      await this.bookingRepository.insertStatusLog(conn, booking.id, {
        fromStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
        toStatus: BOOKING_STATUS.OPEN,
        changedByUserId: driver.user_id,
        changedByRole: ROLES.DRIVER,
        reason: ASSIGNMENT_RELEASE_MARKER,
        memo: evaluation.reasonCode,
      });
      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: ASSIGNMENT_RELEASE_MARKER,
        actorUserId: driver.user_id,
        actorRole: ROLES.DRIVER,
        description: evaluation.emergency
          ? 'Driver released assignment as emergency reassignment'
          : 'Driver released assignment before trip start',
        payload: {
          bookingNumber: normalizedBookingNumber,
          driverId: driver.id,
          assignmentId: active.id,
          reasonCode: evaluation.reasonCode,
          reasonDetail: evaluation.reasonDetail,
          reassignmentPriority: evaluation.reassignmentPriority,
          remainingMs: evaluation.remainingMs,
          emergency: evaluation.emergency,
          // Single reopen event; urgency is carried by reassignmentPriority.
          eventName: 'BOOKING_REOPENED_FOR_DISPATCH',
        },
      });
      await this.deactivateReleasedDriverChatParticipant(
        conn,
        booking,
        driver.user_id,
      );

      const openRow = await this.bookingRepository.findOpenDriverCallByBookingId(
        conn,
        booking.id,
      );
      if (!openRow) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }
      openCallPayload = {
        ...this.mapOpenCall(openRow),
        reassignmentPriority: evaluation.reassignmentPriority,
        releasedByDriver: true,
      };
      openCallTargets = await this.notifyEligibleDriversForReopenedBooking(conn, {
        booking,
        openCallPayload,
        releasedAssignmentId: active.id,
      });

      await conn.commit();
      releasedDriverUserId = driver.user_id;
      releaseResult = {
        bookingNumber: normalizedBookingNumber,
        bookingStatus: BOOKING_STATUS.OPEN,
        status: BOOKING_STATUS.OPEN,
        assignmentStatus: 'CANCELLED',
        released: true,
        reassignmentPriority: evaluation.reassignmentPriority,
        scheduledPickupAt: booking.scheduled_pickup_at,
        reasonCode: evaluation.reasonCode,
        message: 'Assignment released and booking reopened for dispatch.',
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    emitDriverAssignmentReleased(releasedDriverUserId, {
      bookingNumber: normalizedBookingNumber,
      status: BOOKING_STATUS.OPEN,
      reason: 'DRIVER_RELEASED',
      reasonCode: 'DRIVER_RELEASED',
      bookingStatus: BOOKING_STATUS.OPEN,
      reassignmentPriority: releaseResult?.reassignmentPriority,
      releasedAt: new Date().toISOString(),
    });
    emitDriverCallClaimed({ bookingNumber: normalizedBookingNumber });
    for (const target of openCallTargets) {
      emitDriverCallAvailable(target.userId, openCallPayload);
    }

    return releaseResult;
  }
}

module.exports = DriverCallService;
