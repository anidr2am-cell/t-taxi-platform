const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const {
  formatServiceDateTimeForApi,
  parseServiceDateTimeToMs,
} = require('../utils/serviceDateTime.util');
const { assertNoPickupTimeConflict } = require('../policies/driverBookingConflictPolicy');
const {
  emitDriverUrgentCallEtaRequired,
  emitDriverUrgentCallLocked,
  emitBookingUrgentNegotiationEtaProposed,
  emitDriverUrgentCallConfirmed,
  emitBookingUrgentNegotiationConfirmed,
  emitDriverUrgentCallRoundEnded,
  emitDriverUrgentCallUnlocked,
  emitDriverUrgentCallNew,
  emitDriverUrgentCallCancelled,
  emitBookingUrgentNegotiationCancelled,
  emitBookingUrgentNegotiationExpired,
} = require('../socket/realtime');
const URGENT_NEGOTIATION_TIMEOUT_CONFIG = require('../constants/urgentNegotiationTimeoutConfig');
const logger = require('../utils/logger');

class UrgentNegotiationService {
  constructor(
    pool,
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
    bookingRepository,
    bookingService,
    chatService,
  ) {
    this.pool = pool;
    this.urgentNegotiationRepository = urgentNegotiationRepository;
    this.driverRepository = driverRepository;
    this.driverJobService = driverJobService;
    this.bookingRepository = bookingRepository;
    this.bookingService = bookingService;
    this.chatService = chatService;
  }
  throwAppError(message, { statusCode, errorCode, errors } = {}) {
    throw new AppError(message, { statusCode, errorCode, errors });
  }

  normalizeEtaMinutes(rawEtaMinutes) {
    const numeric = Number(rawEtaMinutes);
    if (!Number.isInteger(numeric) || numeric <= 0) {
      this.throwAppError('ETA minutes must be a positive integer', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.URGENT_ETA_INVALID,
      });
    }
    return numeric;
  }

  remainingMinutesUntilPickup(scheduledPickupAt, nowMs = Date.now()) {
    const pickupMs = parseServiceDateTimeToMs(scheduledPickupAt);
    if (pickupMs == null) {
      this.throwAppError('Booking pickup time is invalid for urgent ETA submission', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.URGENT_ETA_INVALID,
      });
    }
    return Math.floor((pickupMs - nowMs) / (60 * 1000));
  }

  assertEtaWithinPickupWindow(scheduledPickupAt, etaMinutes, nowMs = Date.now()) {
    const remainingMinutes = this.remainingMinutesUntilPickup(scheduledPickupAt, nowMs);
    if (etaMinutes > remainingMinutes) {
      this.throwAppError('ETA exceeds remaining time until pickup', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.URGENT_ETA_EXCEEDS_PICKUP_WINDOW,
      });
    }
  }

  assertEtaFasterThanPreviousRejection(minRequiredEtaMinutes, etaMinutes) {
    if (minRequiredEtaMinutes == null) return;
    const minimum = Number(minRequiredEtaMinutes);
    if (!Number.isFinite(minimum)) return;
    if (etaMinutes >= minimum) {
      this.throwAppError(
        `이전 제안(${minimum}분)보다 빠른 시간을 입력해주세요`,
        {
          statusCode: HTTP_STATUS.UNPROCESSABLE,
          errorCode: ERROR_CODES.URGENT_ETA_NOT_FAST_ENOUGH,
          errors: [{ minRequiredEtaMinutes: minimum, submittedEtaMinutes: etaMinutes }],
        },
      );
    }
  }

  assertLockWindowOpen(lockExpiresAt, nowMs = Date.now()) {
    const expiresMs = parseServiceDateTimeToMs(lockExpiresAt);
    if (expiresMs == null || nowMs >= expiresMs) {
      this.throwAppError('Driver ETA submission window has expired', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_ETA_WINDOW_EXPIRED,
      });
    }
  }

  assertDecisionWindowOpen(customerDecisionExpiresAt, nowMs = Date.now()) {
    const expiresMs = parseServiceDateTimeToMs(customerDecisionExpiresAt);
    if (expiresMs == null || nowMs >= expiresMs) {
      this.throwAppError('Customer decision window has expired', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_DECISION_WINDOW_EXPIRED,
      });
    }
  }

  isExpiredTimestamp(timestamp, nowMs = Date.now()) {
    const expiresMs = parseServiceDateTimeToMs(timestamp);
    return expiresMs != null && nowMs >= expiresMs;
  }

  normalizeCustomerDecision(decision) {
    const normalized = String(decision ?? '').trim().toUpperCase();
    if (normalized !== 'ACCEPT' && normalized !== 'REJECT') {
      this.throwAppError('Decision must be ACCEPT or REJECT', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return normalized;
  }

  resolveCustomerActorId(authUser) {
    if (authUser?.id) return authUser.id;
    return null;
  }
  async lockNegotiation(driverUserId, bookingNumber) {
    const normalizedBookingNumber = this.driverJobService.validateBookingNumber(bookingNumber);
    const normalizedDriverUserId = Number(driverUserId);
    if (!Number.isFinite(normalizedDriverUserId) || normalizedDriverUserId <= 0) {
      this.throwAppError('Invalid driver user id', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    let lockResult = null;
    let driverUserIdForEmit = normalizedDriverUserId;

    try {
      await conn.beginTransaction();

      const driver = await this.driverRepository.findByUserIdForUpdate(
        conn,
        normalizedDriverUserId,
      );
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        this.throwAppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }

      const booking = await this.urgentNegotiationRepository.findBookingForUrgentLock(
        conn,
        normalizedBookingNumber,
      );
      if (!booking) {
        this.throwAppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }
      if (!Number(booking.is_urgent_request)) {
        this.throwAppError('Booking is not an urgent request', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.URGENT_NOT_URGENT_BOOKING,
        });
      }

      const negotiation = await this.urgentNegotiationRepository.findBroadcastingNegotiationForUpdate(
        conn,
        booking.id,
      );
      if (!negotiation) {
        this.throwAppError('Urgent negotiation is not accepting locks', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_BROADCASTING,
        });
      }

      const affectedRows = await this.urgentNegotiationRepository.lockNegotiationIfBroadcasting(
        conn,
        {
          negotiationId: negotiation.id,
          driverId: driver.id,
        },
      );
      if (affectedRows !== 1) {
        this.throwAppError('Another driver has already locked this urgent call', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_ALREADY_LOCKED,
        });
      }

      const attemptNumber = Number(negotiation.attempt_count || 0) + 1;
      const attemptId = await this.urgentNegotiationRepository.insertAttempt(conn, {
        negotiationId: negotiation.id,
        attemptNumber,
        driverId: driver.id,
      });

      const lockedNegotiation = await this.urgentNegotiationRepository.findNegotiationById(
        conn,
        negotiation.id,
      );

      lockResult = {
        bookingNumber: normalizedBookingNumber,
        bookingId: booking.id,
        negotiationId: negotiation.id,
        attemptId,
        attemptNumber,
        driverId: driver.id,
        status: lockedNegotiation?.status || 'LOCKED',
        lockExpiresAt: formatServiceDateTimeForApi(
          lockedNegotiation?.lock_expires_at,
        ),
      };
      driverUserIdForEmit = driver.user_id;

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    const socketPayload = {
      bookingNumber: lockResult.bookingNumber,
      negotiationId: lockResult.negotiationId,
      attemptNumber: lockResult.attemptNumber,
      lockExpiresAt: lockResult.lockExpiresAt,
    };

    emitDriverUrgentCallEtaRequired(driverUserIdForEmit, socketPayload);
    emitDriverUrgentCallLocked({
      ...socketPayload,
      lockedDriverId: lockResult.driverId,
    });

    return lockResult;
  }

  async submitEta(driverUserId, bookingNumber, etaMinutes, options = {}) {
    const normalizedBookingNumber = this.driverJobService.validateBookingNumber(bookingNumber);
    const normalizedDriverUserId = Number(driverUserId);
    const normalizedEtaMinutes = this.normalizeEtaMinutes(etaMinutes);
    const nowMs = options.nowMs ?? Date.now();

    if (!Number.isFinite(normalizedDriverUserId) || normalizedDriverUserId <= 0) {
      this.throwAppError('Invalid driver user id', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    let submitResult = null;

    try {
      await conn.beginTransaction();

      const driver = await this.driverRepository.findByUserIdForUpdate(
        conn,
        normalizedDriverUserId,
      );
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        this.throwAppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }

      const booking = await this.urgentNegotiationRepository.findBookingForUrgentLock(
        conn,
        normalizedBookingNumber,
      );
      if (!booking) {
        this.throwAppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }

      const negotiation = await this.urgentNegotiationRepository.findNegotiationByBookingIdForUpdate(
        conn,
        booking.id,
      );
      if (!negotiation) {
        this.throwAppError('Urgent negotiation not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_FOUND,
        });
      }

      if (negotiation.status !== 'LOCKED') {
        this.throwAppError('Urgent negotiation is not locked for ETA submission', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NOT_LOCKED,
        });
      }

      if (Number(negotiation.locked_driver_id) !== Number(driver.id)) {
        this.throwAppError('Only the locked driver can submit ETA', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.URGENT_NOT_LOCKED_DRIVER,
        });
      }

      this.assertLockWindowOpen(negotiation.lock_expires_at, nowMs);
      this.assertEtaWithinPickupWindow(booking.scheduled_pickup_at, normalizedEtaMinutes, nowMs);
      this.assertEtaFasterThanPreviousRejection(
        negotiation.min_required_eta_minutes,
        normalizedEtaMinutes,
      );

      const updatedNegotiation = await this.urgentNegotiationRepository.markNegotiationAwaitingCustomer(
        conn,
        negotiation.id,
      );
      if (!updatedNegotiation) {
        this.throwAppError('Urgent negotiation is not locked for ETA submission', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NOT_LOCKED,
        });
      }

      const attemptUpdated = await this.urgentNegotiationRepository.updateLatestAttemptEta(
        conn,
        {
          negotiationId: negotiation.id,
          etaMinutes: normalizedEtaMinutes,
        },
      );
      if (attemptUpdated !== 1) {
        this.throwAppError('Urgent negotiation attempt not found for ETA submission', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NOT_LOCKED,
        });
      }

      const latestAttempt = await this.urgentNegotiationRepository.findLatestAttempt(
        conn,
        negotiation.id,
      );

      submitResult = {
        bookingNumber: normalizedBookingNumber,
        bookingId: booking.id,
        negotiationId: negotiation.id,
        attemptNumber: latestAttempt?.attempt_number ?? null,
        driverId: driver.id,
        status: updatedNegotiation.status,
        etaMinutes: normalizedEtaMinutes,
        customerDecisionExpiresAt: formatServiceDateTimeForApi(
          updatedNegotiation.customer_decision_expires_at,
        ),
      };

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    emitBookingUrgentNegotiationEtaProposed(submitResult.bookingId, {
      bookingNumber: submitResult.bookingNumber,
      negotiationId: submitResult.negotiationId,
      attemptNumber: submitResult.attemptNumber,
      etaMinutes: submitResult.etaMinutes,
      expiresAt: submitResult.customerDecisionExpiresAt,
    });

    return submitResult;
  }

  async submitCustomerDecision(bookingNumber, decision, options = {}) {
    const normalizedBookingNumber = this.driverJobService.validateBookingNumber(bookingNumber);
    const normalizedDecision = this.normalizeCustomerDecision(decision);
    const authUser = options.authUser ?? null;
    const guestAccessToken = options.guestAccessToken ?? null;
    const nowMs = options.nowMs ?? Date.now();

    const conn = await this.pool.getConnection();
    let decisionResult = null;
    let socketActions = [];

    try {
      await conn.beginTransaction();

      const booking = await this.urgentNegotiationRepository.findBookingForUrgentLock(
        conn,
        normalizedBookingNumber,
      );
      if (!booking) {
        this.throwAppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }

      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );

      const negotiation = await this.urgentNegotiationRepository.findNegotiationByBookingIdForUpdate(
        conn,
        booking.id,
      );
      if (!negotiation) {
        this.throwAppError('Urgent negotiation not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_FOUND,
        });
      }

      if (negotiation.status !== 'AWAITING_CUSTOMER') {
        this.throwAppError('Urgent negotiation is not awaiting customer decision', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
        });
      }

      this.assertDecisionWindowOpen(negotiation.customer_decision_expires_at, nowMs);

      const latestAttempt = await this.urgentNegotiationRepository.findLatestAttempt(
        conn,
        negotiation.id,
      );
      if (!latestAttempt?.proposed_eta_minutes) {
        this.throwAppError('Urgent negotiation is not awaiting customer decision', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
        });
      }

      const actorUserId = this.resolveCustomerActorId(authUser);
      const attemptOutcome = normalizedDecision === 'ACCEPT'
        ? 'CUSTOMER_ACCEPTED'
        : 'CUSTOMER_REJECTED';

      const attemptUpdated = await this.urgentNegotiationRepository.updateLatestAttemptOutcome(
        conn,
        {
          negotiationId: negotiation.id,
          outcome: attemptOutcome,
        },
      );
      if (attemptUpdated !== 1) {
        this.throwAppError('Urgent negotiation is not awaiting customer decision', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
        });
      }

      if (normalizedDecision === 'ACCEPT') {
        decisionResult = await this.handleCustomerAccept(conn, {
          booking,
          negotiation,
          latestAttempt,
          actorUserId,
        });
      } else {
        decisionResult = await this.handleCustomerReject(conn, {
          booking,
          negotiation,
          latestAttempt,
          actorUserId,
        });
        socketActions = decisionResult.socketActions || [];
        delete decisionResult.socketActions;
      }

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    if (normalizedDecision === 'ACCEPT') {
      emitDriverUrgentCallConfirmed(decisionResult.lockedDriverUserId, {
        bookingNumber: decisionResult.bookingNumber,
        negotiationId: decisionResult.negotiationId,
        attemptNumber: decisionResult.attemptNumber,
        bookingStatus: decisionResult.bookingStatus,
      });
      emitBookingUrgentNegotiationConfirmed(decisionResult.bookingId, {
        bookingNumber: decisionResult.bookingNumber,
        negotiationId: decisionResult.negotiationId,
        attemptNumber: decisionResult.attemptNumber,
        bookingStatus: decisionResult.bookingStatus,
      });
    } else {
      for (const action of socketActions) {
        action();
      }
    }

    return decisionResult;
  }

  async handleCustomerAccept(conn, {
    booking,
    negotiation,
    latestAttempt,
    actorUserId,
  }) {
    const lockedDriver = await this.driverRepository.findByIdForUpdate(
      conn,
      negotiation.locked_driver_id,
    );
    if (!lockedDriver || !lockedDriver.is_active) {
      this.throwAppError('Locked driver not found', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }

    if (booking.status !== BOOKING_STATUS.OPEN) {
      this.throwAppError('Booking is no longer open for urgent confirmation', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
      });
    }

    const activeAssignment = await this.bookingRepository.findActiveAssignmentForUpdate(
      conn,
      booking.id,
    );
    if (activeAssignment) {
      this.throwAppError('Booking already has an active driver assignment', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
      });
    }

    const conflictRows = await this.driverRepository.findActiveAssignmentPickupsForConflict(
      conn,
      lockedDriver.id,
      booking.id,
    );
    assertNoPickupTimeConflict(conflictRows, booking.scheduled_pickup_at, {
      excludeBookingId: booking.id,
    });

    const vehicle = await this.driverRepository.findMatchingVehicle(
      conn,
      lockedDriver.id,
      booking.vehicle_type_id,
    );
    if (!vehicle) {
      this.throwAppError('Driver vehicle type does not match booking', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }

    const confirmedNegotiation = await this.urgentNegotiationRepository.confirmNegotiation(
      conn,
      negotiation.id,
    );
    if (!confirmedNegotiation) {
      this.throwAppError('Urgent negotiation is not awaiting customer decision', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
      });
    }

    const assignmentId = await this.bookingRepository.insertDriverAssignment(conn, {
      bookingId: booking.id,
      driverId: lockedDriver.id,
      driverVehicleId: vehicle.id,
      assignedByUserId: actorUserId ?? lockedDriver.user_id,
      assignmentReason: 'URGENT_CUSTOMER_CONFIRMED',
    });

    await this.bookingRepository.updateStatus(
      conn,
      booking.id,
      BOOKING_STATUS.DRIVER_ASSIGNED,
      actorUserId ?? lockedDriver.user_id,
    );
    await this.bookingRepository.insertStatusLog(conn, booking.id, {
      fromStatus: BOOKING_STATUS.OPEN,
      toStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
      changedByUserId: actorUserId,
      changedByRole: ROLES.CUSTOMER,
      reason: 'URGENT_CUSTOMER_CONFIRMED',
    });
    await this.bookingRepository.insertActivityLog(conn, booking.id, {
      activityType: 'URGENT_CUSTOMER_CONFIRMED',
      actorUserId,
      actorRole: ROLES.CUSTOMER,
      description: 'Customer accepted urgent driver ETA proposal',
      payload: {
        bookingNumber: booking.booking_number,
        negotiationId: negotiation.id,
        driverId: lockedDriver.id,
        assignmentId,
        etaMinutes: latestAttempt.proposed_eta_minutes,
      },
    });

    if (this.chatService) {
      const room = await this.chatService.ensureRoom(conn, booking);
      await this.chatService.ensureDriverParticipant(
        conn,
        room,
        { ...booking, status: BOOKING_STATUS.DRIVER_ASSIGNED },
        lockedDriver.user_id,
      );
    }

    return {
      bookingNumber: booking.booking_number,
      bookingId: booking.id,
      negotiationId: negotiation.id,
      attemptNumber: latestAttempt.attempt_number,
      driverId: lockedDriver.id,
      status: confirmedNegotiation.status,
      decision: 'ACCEPT',
      etaMinutes: latestAttempt.proposed_eta_minutes,
      assignmentId,
      bookingStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
      lockedDriverUserId: lockedDriver.user_id,
    };
  }

  buildRoundEndedSocketActions({
    booking,
    negotiationId,
    attemptNumber,
    attemptCount,
    minRequiredEtaMinutes,
    driverUserId,
  }) {
    const socketActions = [];
    const broadcastPayload = {
      bookingNumber: booking.booking_number,
      negotiationId,
      attemptCount,
      minRequiredEtaMinutes: minRequiredEtaMinutes ?? null,
    };

    if (driverUserId) {
      socketActions.push(
        () => emitDriverUrgentCallRoundEnded(driverUserId, {
          ...broadcastPayload,
          attemptNumber,
        }),
      );
    }
    socketActions.push(
      () => emitDriverUrgentCallUnlocked(broadcastPayload),
      () => emitDriverUrgentCallNew(broadcastPayload),
    );
    return socketActions;
  }

  buildCancelledSocketActions({ booking, negotiationId, attemptCount }) {
    const cancelledPayload = {
      bookingNumber: booking.booking_number,
      negotiationId,
      attemptCount,
      closedReason: 'URGENT_NEGOTIATION_EXHAUSTED',
    };
    return [
      () => emitDriverUrgentCallCancelled(cancelledPayload),
      () => emitBookingUrgentNegotiationCancelled(booking.id, cancelledPayload),
    ];
  }

  async completeFailedNegotiationRound(conn, {
    booking,
    negotiation,
    latestAttempt,
    fromStatus,
    minRequiredEtaMinutes = undefined,
    actorUserId = null,
    activityType,
    activityDescription,
  }) {
    const timedOutDriver = await this.driverRepository.findById(
      negotiation.locked_driver_id,
    );
    const nextAttemptCount = Number(negotiation.attempt_count || 0) + 1;
    const socketActions = [];

    if (nextAttemptCount >= URGENT_NEGOTIATION_TIMEOUT_CONFIG.MAX_ATTEMPTS) {
      const cancelledNegotiation = await this.urgentNegotiationRepository.cancelAfterAttemptFailure(
        conn,
        {
          negotiationId: negotiation.id,
          fromStatus,
          minRequiredEtaMinutes,
        },
      );
      if (!cancelledNegotiation) {
        this.throwAppError('Urgent negotiation is not awaiting timeout processing', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
        });
      }

      await this.bookingRepository.updateStatus(
        conn,
        booking.id,
        BOOKING_STATUS.CANCELLED,
        actorUserId,
        { cancellationReason: 'URGENT_NEGOTIATION_EXHAUSTED' },
      );
      await this.bookingRepository.insertStatusLog(conn, booking.id, {
        fromStatus: booking.status,
        toStatus: BOOKING_STATUS.CANCELLED,
        changedByUserId: actorUserId,
        changedByRole: ROLES.CUSTOMER,
        reason: 'URGENT_NEGOTIATION_EXHAUSTED',
      });
      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType,
        actorUserId,
        actorRole: ROLES.CUSTOMER,
        description: activityDescription,
        payload: {
          bookingNumber: booking.booking_number,
          negotiationId: negotiation.id,
          attemptCount: nextAttemptCount,
        },
      });

      socketActions.push(...this.buildCancelledSocketActions({
        booking,
        negotiationId: negotiation.id,
        attemptCount: nextAttemptCount,
      }));

      return {
        bookingNumber: booking.booking_number,
        bookingId: booking.id,
        negotiationId: negotiation.id,
        attemptNumber: latestAttempt?.attempt_number ?? null,
        status: cancelledNegotiation.status,
        attemptCount: nextAttemptCount,
        minRequiredEtaMinutes: minRequiredEtaMinutes ?? negotiation.min_required_eta_minutes,
        bookingStatus: BOOKING_STATUS.CANCELLED,
        closedReason: 'URGENT_NEGOTIATION_EXHAUSTED',
        socketActions,
      };
    }

    const rebroadcastNegotiation = await this.urgentNegotiationRepository.rebroadcastAfterAttemptFailure(
      conn,
      {
        negotiationId: negotiation.id,
        fromStatus,
        minRequiredEtaMinutes,
      },
    );
    if (!rebroadcastNegotiation) {
      this.throwAppError('Urgent negotiation is not awaiting timeout processing', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
      });
    }

    socketActions.push(...this.buildRoundEndedSocketActions({
      booking,
      negotiationId: negotiation.id,
      attemptNumber: latestAttempt?.attempt_number ?? null,
      attemptCount: nextAttemptCount,
      minRequiredEtaMinutes: minRequiredEtaMinutes ?? rebroadcastNegotiation.min_required_eta_minutes,
      driverUserId: timedOutDriver?.user_id ?? null,
    }));

    if (fromStatus === 'AWAITING_CUSTOMER') {
      socketActions.push(
        () => emitBookingUrgentNegotiationExpired(booking.id, {
          bookingNumber: booking.booking_number,
          negotiationId: negotiation.id,
          attemptCount: nextAttemptCount,
        }),
      );
    }

    return {
      bookingNumber: booking.booking_number,
      bookingId: booking.id,
      negotiationId: negotiation.id,
      attemptNumber: latestAttempt?.attempt_number ?? null,
      status: rebroadcastNegotiation.status,
      attemptCount: nextAttemptCount,
      minRequiredEtaMinutes: rebroadcastNegotiation.min_required_eta_minutes,
      bookingStatus: booking.status,
      socketActions,
    };
  }

  async handleCustomerReject(conn, {
    booking,
    negotiation,
    latestAttempt,
    actorUserId,
  }) {
    const roundResult = await this.completeFailedNegotiationRound(conn, {
      booking,
      negotiation,
      latestAttempt,
      fromStatus: 'AWAITING_CUSTOMER',
      minRequiredEtaMinutes: Number(latestAttempt.proposed_eta_minutes),
      actorUserId,
      activityType: 'URGENT_NEGOTIATION_EXHAUSTED',
      activityDescription: 'Urgent negotiation exhausted after customer rejections',
    });

    return {
      ...roundResult,
      decision: 'REJECT',
    };
  }

  async processExpiredNegotiations(options = {}) {
    const batchSize = options.batchSize ?? URGENT_NEGOTIATION_TIMEOUT_CONFIG.DEFAULT_BATCH_SIZE;
    const nowMs = options.nowMs ?? Date.now();
    const startedAt = Date.now();
    const socketActions = [];
    let lockedSelected = 0;
    let lockedProcessed = 0;
    let lockedFailed = 0;
    let customerSelected = 0;
    let customerProcessed = 0;
    let customerFailed = 0;

    const expiredLocked = await this.urgentNegotiationRepository.listExpiredLockedNegotiations(
      batchSize,
    );
    lockedSelected = expiredLocked.length;

    for (const row of expiredLocked) {
      try {
        const result = await this.processDriverEtaTimeout(row.id, { nowMs });
        if (result?.socketActions?.length) {
          socketActions.push(...result.socketActions);
        }
        lockedProcessed += 1;
      } catch (err) {
        lockedFailed += 1;
        logger.warn('Urgent negotiation driver ETA timeout processing failed', {
          negotiationId: row.id,
          bookingNumber: row.booking_number,
          error: err.message,
          errorCode: err.errorCode,
        });
      }
    }

    const expiredAwaiting = await this.urgentNegotiationRepository
      .listExpiredAwaitingCustomerNegotiations(batchSize);
    customerSelected = expiredAwaiting.length;

    for (const row of expiredAwaiting) {
      try {
        const result = await this.processCustomerDecisionTimeout(row.id, { nowMs });
        if (result?.socketActions?.length) {
          socketActions.push(...result.socketActions);
        }
        customerProcessed += 1;
      } catch (err) {
        customerFailed += 1;
        logger.warn('Urgent negotiation customer decision timeout processing failed', {
          negotiationId: row.id,
          bookingNumber: row.booking_number,
          error: err.message,
          errorCode: err.errorCode,
        });
      }
    }

    for (const action of socketActions) {
      action();
    }

    return {
      lockedSelected,
      lockedProcessed,
      lockedFailed,
      customerSelected,
      customerProcessed,
      customerFailed,
      durationMs: Date.now() - startedAt,
    };
  }

  async processDriverEtaTimeout(negotiationId, options = {}) {
    const nowMs = options.nowMs ?? Date.now();
    const conn = await this.pool.getConnection();
    let result = null;

    try {
      await conn.beginTransaction();

      const negotiation = await this.urgentNegotiationRepository.findNegotiationByIdForUpdate(
        conn,
        negotiationId,
      );
      if (!negotiation || negotiation.status !== 'LOCKED') {
        await conn.commit();
        return null;
      }

      if (!this.isExpiredTimestamp(negotiation.lock_expires_at, nowMs)) {
        await conn.commit();
        return null;
      }

      const booking = await this.urgentNegotiationRepository.findBookingForUrgentLockById(
        conn,
        negotiation.booking_id,
      );
      if (!booking) {
        this.throwAppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }

      const latestAttempt = await this.urgentNegotiationRepository.findLatestAttempt(
        conn,
        negotiation.id,
      );
      const attemptUpdated = await this.urgentNegotiationRepository.updateLatestAttemptOutcome(
        conn,
        {
          negotiationId: negotiation.id,
          outcome: 'DRIVER_ETA_TIMEOUT',
        },
      );
      if (attemptUpdated !== 1) {
        this.throwAppError('Urgent negotiation attempt not found for ETA timeout', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NOT_LOCKED,
        });
      }

      result = await this.completeFailedNegotiationRound(conn, {
        booking,
        negotiation,
        latestAttempt,
        fromStatus: 'LOCKED',
        activityType: 'URGENT_DRIVER_ETA_TIMEOUT',
        activityDescription: 'Driver failed to submit ETA before lock expired',
      });

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    if (result?.socketActions?.length) {
      for (const action of result.socketActions) {
        action();
      }
      delete result.socketActions;
    }

    return result;
  }

  async processCustomerDecisionTimeout(negotiationId, options = {}) {
    const nowMs = options.nowMs ?? Date.now();
    const conn = await this.pool.getConnection();
    let result = null;

    try {
      await conn.beginTransaction();

      const negotiation = await this.urgentNegotiationRepository.findNegotiationByIdForUpdate(
        conn,
        negotiationId,
      );
      if (!negotiation || negotiation.status !== 'AWAITING_CUSTOMER') {
        await conn.commit();
        return null;
      }

      if (!this.isExpiredTimestamp(negotiation.customer_decision_expires_at, nowMs)) {
        await conn.commit();
        return null;
      }

      const booking = await this.urgentNegotiationRepository.findBookingForUrgentLockById(
        conn,
        negotiation.booking_id,
      );
      if (!booking) {
        this.throwAppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }

      const latestAttempt = await this.urgentNegotiationRepository.findLatestAttempt(
        conn,
        negotiation.id,
      );
      if (!latestAttempt?.proposed_eta_minutes) {
        this.throwAppError('Urgent negotiation is not awaiting customer decision', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
        });
      }

      const attemptUpdated = await this.urgentNegotiationRepository.updateLatestAttemptOutcome(
        conn,
        {
          negotiationId: negotiation.id,
          outcome: 'CUSTOMER_AUTO_REJECTED',
        },
      );
      if (attemptUpdated !== 1) {
        this.throwAppError('Urgent negotiation is not awaiting customer decision', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
        });
      }

      result = await this.completeFailedNegotiationRound(conn, {
        booking,
        negotiation,
        latestAttempt,
        fromStatus: 'AWAITING_CUSTOMER',
        minRequiredEtaMinutes: Number(latestAttempt.proposed_eta_minutes),
        activityType: 'URGENT_CUSTOMER_AUTO_REJECTED',
        activityDescription: 'Customer decision window expired without response',
      });

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    if (result?.socketActions?.length) {
      for (const action of result.socketActions) {
        action();
      }
      delete result.socketActions;
    }

    return {
      ...result,
      decision: 'AUTO_REJECT',
    };
  }

  async getCustomerNegotiationStatus(bookingNumber, options = {}) {
    const normalizedBookingNumber = this.driverJobService.validateBookingNumber(bookingNumber);
    const authUser = options.authUser ?? null;
    const guestAccessToken = options.guestAccessToken ?? null;

    const conn = await this.pool.getConnection();
    try {
      const booking = await this.urgentNegotiationRepository.findBookingForCustomer(
        conn,
        normalizedBookingNumber,
      );
      if (!booking) {
        this.throwAppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }
      if (!Number(booking.is_urgent_request)) {
        this.throwAppError('Booking is not an urgent request', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }

      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );

      const negotiation = await this.urgentNegotiationRepository.findNegotiationByBookingId(
        conn,
        booking.id,
      );
      if (!negotiation) {
        this.throwAppError('Urgent negotiation not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_FOUND,
        });
      }

      const latestAttempt = await this.urgentNegotiationRepository.findLatestAttempt(
        conn,
        negotiation.id,
      );

      return {
        bookingNumber: booking.booking_number,
        bookingId: booking.id,
        bookingStatus: booking.status,
        negotiationId: negotiation.id,
        status: negotiation.status,
        attemptCount: Number(negotiation.attempt_count || 0),
        minRequiredEtaMinutes: negotiation.min_required_eta_minutes,
        proposedEtaMinutes: latestAttempt?.proposed_eta_minutes ?? null,
        customerDecisionExpiresAt: formatServiceDateTimeForApi(
          negotiation.customer_decision_expires_at,
        ),
        closedReason: negotiation.status === 'CANCELLED'
          ? negotiation.closed_reason
          : null,
      };
    } finally {
      conn.release();
    }
  }
}
module.exports = UrgentNegotiationService;
