const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const {
  emitDriverCallClaimed,
  emitDriverCallConfirmed,
} = require('../socket/realtime');
const {
  assertNoPickupTimeConflict,
} = require('../policies/driverBookingConflictPolicy');
const {
  ASSIGNMENT_RELEASE_MARKER,
  evaluateDriverAssignmentRelease,
  RELEASE_BLOCKED_REASON,
} = require('../policies/driverAssignmentRelease.policy');
const {
  isVehicleCompatibleWithBooking,
} = require('../utils/vehicleMatchTier');

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
    urgentNegotiationRepository = null,
    bookingAssignmentReopenService = null,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.driverJobService = driverJobService;
    this.notificationRepository = notificationRepository;
    this.chatRepository = chatRepository;
    this.commissionSettlementService = commissionSettlementService;
    this.urgentNegotiationRepository = urgentNegotiationRepository;
    this.bookingAssignmentReopenService = bookingAssignmentReopenService;
  }

  validateBookingNumber(bookingNumber) {
    return this.driverJobService.validateBookingNumber(bookingNumber);
  }

  passengerCount(row) {
    return Number(row.adults || 0) + Number(row.children || 0) + Number(row.infants || 0);
  }

  mapCompatibleVehicles(driverVehicles, bookingVehicleCode) {
    return (driverVehicles || [])
      .filter((vehicle) => isVehicleCompatibleWithBooking(
        vehicle.vehicle_type_code,
        bookingVehicleCode,
      ))
      .map((vehicle) => ({
        driverVehicleId: Number(vehicle.id),
        vehicleTypeCode: vehicle.vehicle_type_code,
        vehicleTypeName: vehicle.vehicle_type_name,
        plateNumber: vehicle.plate_number,
        isExactMatch:
          String(vehicle.vehicle_type_code || '').toUpperCase()
          === String(bookingVehicleCode || '').toUpperCase(),
      }));
  }

  mapOpenCall(row, driverVehicles = []) {
    const paymentSummary = this.driverJobService.paymentSummary
      ? this.driverJobService.paymentSummary(row)
      : {};
    const compatibleVehicles = this.mapCompatibleVehicles(
      driverVehicles,
      row.vehicle_type_code,
    );
    const metadata = this.driverJobService.metadata(row);
    const originLocation = metadata.originLocation ?? {};
    const destinationLocation = metadata.destinationLocation ?? {};
    return {
      bookingNumber: row.booking_number,
      status: row.status,
      scheduledPickupAt: row.scheduled_pickup_at,
      pickupDate: row.pickup_date,
      pickupTime: row.pickup_time,
      origin: row.origin_address,
      destination: row.destination_address,
      pickupLocation: this.driverJobService.locationDetails({
        name: originLocation.name,
        address: row.origin_address,
        placeId: row.origin_place_id,
        latitude: row.origin_lat,
        longitude: row.origin_lng,
      }),
      destinationLocation: this.driverJobService.locationDetails({
        name: destinationLocation.name,
        address: row.destination_address,
        placeId: row.destination_place_id,
        latitude: row.destination_lat,
        longitude: row.destination_lng,
      }),
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      nameSignRequested: Boolean(row.name_sign_requested),
      nameSignText: row.name_sign_text || null,
      vehicleType: {
        code: row.vehicle_type_code,
        name: row.vehicle_type_name,
      },
      // EXACT = driver has approved active vehicle of the booking type.
      // COMPATIBLE_UPGRADE = higher-tier hierarchy vehicle covering a lower booking
      // (e.g. VAN driver seeing a SEDAN call). Frontend can badge non-exact rows.
      vehicleMatchType: Number(row.is_exact_vehicle_match) === 1
        ? 'EXACT'
        : 'COMPATIBLE_UPGRADE',
      isExactVehicleMatch: Number(row.is_exact_vehicle_match) === 1,
      compatibleVehicles,
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
      isUrgentRequest: Number(row.is_urgent_request || 0) === 1,
      negotiationId: row.urgent_negotiation_id ?? null,
      minRequiredEtaMinutes: row.urgent_min_required_eta_minutes == null
        ? null
        : Number(row.urgent_min_required_eta_minutes),
    };
  }

  async listOpenCalls(driverUserId) {
    const driver = await this.driverRepository.findByUserId(driverUserId);
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    if (this.commissionSettlementService) {
      if (await this.commissionSettlementService.driverHasBlockingSettlement(driver.id)) {
        return {
          items: [],
          blockedReason: 'UNPAID_SETTLEMENT',
          message: 'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
        };
      }
    }
    const [rows, driverVehicles] = await Promise.all([
      this.bookingRepository.findOpenDriverCallsForDriver(driverUserId),
      this.driverRepository.listApprovedActiveVehicles(driver.id),
    ]);
    return {
      items: rows.map((row) => this.mapOpenCall(row, driverVehicles)),
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

  async assertNoActiveUrgentNegotiation(conn, bookingId) {
    if (!this.urgentNegotiationRepository) return;
    const activeNegotiation = await this.urgentNegotiationRepository
      .findActiveNegotiationForBookingForUpdate(conn, bookingId);
    if (activeNegotiation) {
      throw new AppError('Urgent negotiation is already in progress for this booking', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_ACTIVE,
        errors: [{
          negotiationId: activeNegotiation.id,
          status: activeNegotiation.status,
        }],
      });
    }
  }

  async restartUrgentNegotiationAfterRelease(conn, booking, evaluation) {
    return this.bookingAssignmentReopenService.restartUrgentNegotiationAfterRelease(
      conn,
      booking,
      evaluation,
    );
  }

  assertBookingAssignmentReopenService() {
    if (!this.bookingAssignmentReopenService) {
      throw new AppError('Assignment reopen service is unavailable', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INTERNAL_SERVER_ERROR,
      });
    }
  }

  async claimOpenCall(driverUserId, bookingNumber, input = {}) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const requestedVehicleId = input.driverVehicleId == null
      ? null
      : Number(input.driverVehicleId);
    if (
      requestedVehicleId != null
      && (!Number.isInteger(requestedVehicleId) || requestedVehicleId <= 0)
    ) {
      throw new AppError('driverVehicleId is invalid', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
        errors: [{ field: 'driverVehicleId', message: 'must be a positive integer' }],
      });
    }

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

      if (Number(booking.is_urgent_request)) {
        await this.assertNoActiveUrgentNegotiation(conn, booking.id);
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

      let vehicle;
      if (requestedVehicleId != null) {
        vehicle = await this.driverRepository.findCompatibleVehicleById(
          conn,
          driver.id,
          requestedVehicleId,
          booking.vehicle_type_id,
        );
        if (!vehicle) {
          const owned = await this.driverRepository.findApprovedVehicleByIdForDriver(
            conn,
            driver.id,
            requestedVehicleId,
          );
          if (!owned) {
            throw new AppError('Selected vehicle was not found for this driver', {
              statusCode: HTTP_STATUS.NOT_FOUND,
              errorCode: ERROR_CODES.DRIVER_VEHICLE_NOT_FOUND,
            });
          }
          throw new AppError('Selected vehicle type is not compatible with this booking', {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
          });
        }
      } else {
        vehicle = await this.driverRepository.findMatchingVehicle(
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
          driverVehicleId: vehicle.id,
          vehicleTypeCode: vehicle.vehicle_type_code ?? null,
          plateNumber: vehicle.plate_number ?? null,
          vehicleSelectedByDriver: requestedVehicleId != null,
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

  async notifyEligibleDriversForReopenedBooking(conn, params) {
    return this.bookingAssignmentReopenService.notifyEligibleDriversForReopenedBooking(
      conn,
      params,
    );
  }

  async deactivateReleasedDriverChatParticipant(conn, booking, driverUserId) {
    return this.bookingAssignmentReopenService.deactivateReleasedDriverChatParticipant(
      conn,
      booking,
      driverUserId,
    );
  }

  async releaseAssignment(driverUserId, bookingNumber, input = {}, options = {}) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const conn = await this.pool.getConnection();
    let releasedDriverUserId = driverUserId;
    let openCallPayload = null;
    let openCallTargets = [];
    let urgentRebroadcastPayload = null;
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
      this.assertBookingAssignmentReopenService();

      const reopenEffects = await this.bookingAssignmentReopenService.reopenAssignedBookingInTransaction(
        conn,
        {
          booking,
          bookingNumber: normalizedBookingNumber,
          activeAssignment: active,
          actorUserId: driver.user_id,
          actorRole: ROLES.DRIVER,
          assignmentReleaseMarker: ASSIGNMENT_RELEASE_MARKER,
          assignmentSocketReasonCode: 'DRIVER_RELEASED',
          statusLogMemo: evaluation.reasonCode,
          activityType: ASSIGNMENT_RELEASE_MARKER,
          activityDescription: evaluation.emergency
            ? 'Driver released assignment as emergency reassignment'
            : 'Driver released assignment before trip start',
          activityPayload: {
            bookingNumber: normalizedBookingNumber,
            driverId: driver.id,
            assignmentId: active.id,
            reasonCode: evaluation.reasonCode,
            reasonDetail: evaluation.reasonDetail,
            reassignmentPriority: evaluation.reassignmentPriority,
            remainingMs: evaluation.remainingMs,
            emergency: evaluation.emergency,
            eventName: 'BOOKING_REOPENED_FOR_DISPATCH',
          },
          reassignmentPriority: evaluation.reassignmentPriority,
          releasedByDriver: true,
          releasedDriverUserId: driver.user_id,
          mapOpenCall: (row) => this.mapOpenCall(row),
          urgentEvaluation: evaluation,
        },
      );

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
      openCallPayload = reopenEffects.openCallPayload;
      openCallTargets = reopenEffects.openCallTargets;
      urgentRebroadcastPayload = reopenEffects.urgentRebroadcastPayload;
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    this.bookingAssignmentReopenService.emitReopenEvents({
      bookingNumber: normalizedBookingNumber,
      releasedDriverUserId,
      assignmentSocketReasonCode: 'DRIVER_RELEASED',
      reassignmentPriority: releaseResult?.reassignmentPriority,
      openCallPayload,
      openCallTargets,
      urgentRebroadcastPayload,
    });

    return releaseResult;
  }
}

module.exports = DriverCallService;
