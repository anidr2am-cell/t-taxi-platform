const AppError = require('../utils/AppError');
const { randomUUID } = require('node:crypto');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const { appEvents, EVENTS } = require('../events');
const { isNotificationOutboxEvent } = require('../utils/outboxPayload.util');
const { hashToken } = require('../utils/tokenHash.util');
const {
  evaluateCustomerCancellation,
} = require('../policies/customerBookingCancellation.policy');
const { emitDriverAssignmentReleased } = require('../socket/realtime');

const TERMINAL_STATUSES = new Set([
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.NO_SHOW,
]);

const TRANSITIONS = {
  [BOOKING_STATUS.PENDING]: {
    [BOOKING_STATUS.OPEN]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CONFIRMED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CANCELLED]: [ROLES.CUSTOMER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.NO_SHOW]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.OPEN]: {
    [BOOKING_STATUS.CONFIRMED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.DRIVER_ASSIGNED]: [ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CANCELLED]: [ROLES.CUSTOMER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.NO_SHOW]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.CONFIRMED]: {
    [BOOKING_STATUS.DRIVER_ASSIGNED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CANCELLED]: [ROLES.CUSTOMER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.NO_SHOW]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.DRIVER_ASSIGNED]: {
    [BOOKING_STATUS.ON_ROUTE]: [ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CONFIRMED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    // Customer may cancel until 2h before pickup (policy enforced separately).
    [BOOKING_STATUS.CANCELLED]: [ROLES.CUSTOMER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.NO_SHOW]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.ON_ROUTE]: {
    [BOOKING_STATUS.DRIVER_ARRIVED]: [ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CANCELLED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.NO_SHOW]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.DRIVER_ARRIVED]: {
    [BOOKING_STATUS.PICKED_UP]: [ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CANCELLED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.NO_SHOW]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.PICKED_UP]: {
    [BOOKING_STATUS.SETTLEMENT_PENDING]: [ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN],
    [BOOKING_STATUS.CANCELLED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
  [BOOKING_STATUS.SETTLEMENT_PENDING]: {
    [BOOKING_STATUS.COMPLETED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
  },
};

const EVENT_BY_STATUS = {
  [BOOKING_STATUS.OPEN]: EVENTS.BOOKING_CREATED,
  [BOOKING_STATUS.CONFIRMED]: EVENTS.BOOKING_CONFIRMED,
  [BOOKING_STATUS.DRIVER_ASSIGNED]: EVENTS.DRIVER_ASSIGNED,
  [BOOKING_STATUS.ON_ROUTE]: EVENTS.TRIP_ON_ROUTE,
  [BOOKING_STATUS.DRIVER_ARRIVED]: EVENTS.DRIVER_ARRIVED,
  [BOOKING_STATUS.PICKED_UP]: EVENTS.TRIP_PICKED_UP,
  [BOOKING_STATUS.SETTLEMENT_PENDING]: EVENTS.TRIP_ENDED,
  [BOOKING_STATUS.COMPLETED]: EVENTS.TRIP_COMPLETED,
  [BOOKING_STATUS.CANCELLED]: EVENTS.BOOKING_CANCELLED,
  [BOOKING_STATUS.NO_SHOW]: EVENTS.BOOKING_NO_SHOW,
};

const ACTIVITY_BY_STATUS = {
  [BOOKING_STATUS.OPEN]: 'BOOKING_OPENED',
  [BOOKING_STATUS.CONFIRMED]: 'BOOKING_CONFIRMED',
  [BOOKING_STATUS.DRIVER_ASSIGNED]: 'DRIVER_ASSIGNED',
  [BOOKING_STATUS.ON_ROUTE]: 'TRIP_ON_ROUTE',
  [BOOKING_STATUS.DRIVER_ARRIVED]: 'DRIVER_ARRIVED',
  [BOOKING_STATUS.PICKED_UP]: 'TRIP_PICKED_UP',
  [BOOKING_STATUS.SETTLEMENT_PENDING]: 'SETTLEMENT_PENDING',
  [BOOKING_STATUS.COMPLETED]: 'TRIP_COMPLETED',
  [BOOKING_STATUS.CANCELLED]: 'BOOKING_CANCELLED',
  [BOOKING_STATUS.NO_SHOW]: 'BOOKING_NO_SHOW',
};

const CUSTOMER_CANCEL_MESSAGES = {
  ALREADY_CANCELLED: 'Booking is already cancelled',
  COMPLETED: 'Completed bookings cannot be cancelled',
  NO_SHOW: 'No-show bookings cannot be cancelled',
  TRIP_STARTED: 'Trips that have already started cannot be cancelled',
  WITHIN_TWO_HOURS:
    'Bookings cannot be cancelled within 2 hours of the scheduled pickup time',
  INVALID_PICKUP_TIME: 'Booking pickup time is invalid for cancellation',
};

class BookingStatusService {
  constructor(pool, bookingRepository, outboxRepository, outboxProcessor) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
  }

  validateTransition(fromStatus, toStatus, actorRole) {
    if (TERMINAL_STATUSES.has(fromStatus)) {
      this.throwInvalidTransition(fromStatus, toStatus, actorRole);
    }

    const allowedRoles = TRANSITIONS[fromStatus]?.[toStatus];
    if (!allowedRoles || !allowedRoles.includes(actorRole)) {
      this.throwInvalidTransition(fromStatus, toStatus, actorRole);
    }
  }

  throwInvalidTransition(fromStatus, toStatus, actorRole) {
    throw new AppError(
      `Invalid booking status transition from ${fromStatus} to ${toStatus}`,
      {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        errors: [{ fromStatus, toStatus, actorRole }],
      },
    );
  }

  assertActorCanAccessBooking(booking, actor) {
    if ([ROLES.ADMIN, ROLES.SUPER_ADMIN].includes(actor.role)) {
      return;
    }

    if (actor.role === ROLES.CUSTOMER && booking.customer_user_id === actor.id) {
      return;
    }

    if (actor.role === ROLES.DRIVER && booking.driver_user_id === actor.id) {
      return;
    }

    throw new AppError('Booking is not accessible', {
      statusCode: HTTP_STATUS.FORBIDDEN,
      errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
    });
  }

  evaluateCancellation(booking, nowMs = Date.now()) {
    return evaluateCustomerCancellation({
      status: booking.status,
      scheduledPickupAt: booking.scheduled_pickup_at,
      nowMs,
    });
  }

  assertCustomerCancellationAllowed(booking, nowMs = Date.now()) {
    const evaluation = this.evaluateCancellation(booking, nowMs);
    if (evaluation.canCancel) return evaluation;

    const reason = evaluation.cancellationBlockedReason;
    throw new AppError(
      CUSTOMER_CANCEL_MESSAGES[reason] || 'Booking cannot be cancelled',
      {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        errors: [{
          reason,
          cancellationDeadline: evaluation.cancellationDeadline,
          currentStatus: booking.status,
        }],
      },
    );
  }

  buildEventPayload(booking, fromStatus, toStatus, actor, input) {
    const eventName = EVENT_BY_STATUS[toStatus];
    const payload = {
      eventId: randomUUID(),
      eventName,
      bookingId: booking.id,
      bookingNumber: booking.booking_number,
      previousStatus: fromStatus,
      newStatus: toStatus,
      actorUserId: actor.id ?? null,
      actorRole: actor.role,
      occurredAt: input.occurredAt,
    };

    if (booking.driver_id) {
      payload.driverId = booking.driver_id;
    }
    if (booking.driver_user_id) {
      payload.driverUserId = booking.driver_user_id;
    }

    return payload;
  }

  buildActivityPayload(booking, fromStatus, toStatus, actor, input) {
    const payload = {
      bookingNumber: booking.booking_number,
      previousStatus: fromStatus,
      newStatus: toStatus,
      changedByUserId: actor.id ?? null,
      changedByRole: actor.role,
      occurredAt: input.occurredAt,
    };

    if (booking.driver_id) {
      payload.driverId = booking.driver_id;
    }

    if (input.reason) {
      payload.reason = input.reason;
    }

    if (input.memo) {
      payload.memo = input.memo;
    }

    return payload;
  }

  buildBookingResult(booking, status, idempotent = false, extras = {}) {
    return {
      id: booking.id,
      bookingNumber: booking.booking_number,
      status,
      paymentStatus: booking.payment_status,
      paymentMethod: booking.payment_method,
      totalAmount: Number(booking.total_amount),
      currency: booking.currency,
      idempotent,
      ...extras,
    };
  }

  emitDomainEvent(domainEvent, eventPayload) {
    if (domainEvent === EVENTS.TRIP_COMPLETED) {
      appEvents.emit(domainEvent, eventPayload);
    }
  }

  async dispatchOutboxAfterCommit(outboxId) {
    if (outboxId && this.outboxProcessor) {
      await this.outboxProcessor.dispatchOutboxIds([outboxId]);
    }
  }

  async transitionInTransaction(conn, bookingNumber, input, actor, options = {}) {
    const booking = await this.bookingRepository.findByBookingNumberForUpdate(
      conn,
      bookingNumber,
    );

    if (!booking) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    const fromStatus = booking.status;
    const toStatus = input.status;
    if (!options.skipAccessCheck) {
      this.assertActorCanAccessBooking(booking, actor);
    }

    if (fromStatus === toStatus) {
      return {
        result: this.buildBookingResult(booking, toStatus, true),
        domainEvent: null,
        eventPayload: null,
        outboxId: null,
        releasedDriverUserId: null,
      };
    }

    if (
      toStatus === BOOKING_STATUS.CANCELLED
      && actor.role === ROLES.CUSTOMER
    ) {
      this.assertCustomerCancellationAllowed(booking, options.nowMs);
    }

    this.validateTransition(fromStatus, toStatus, actor.role);
    const occurredAt = new Date().toISOString();
    let releasedDriverUserId = booking.driver_user_id ?? null;

    await this.bookingRepository.updateStatus(conn, booking.id, toStatus, actor.id, {
      cancellationReason: input.reason ?? input.memo ?? null,
    });

    if (toStatus === BOOKING_STATUS.SETTLEMENT_PENDING) {
      await this.bookingRepository.updateCommissionFields(conn, booking.id, {
        commissionStatus: 'DUE',
        commissionAmount: 200,
        commissionDueAt: null,
        updatedBy: actor.id,
      });
    }

    if (toStatus === BOOKING_STATUS.COMPLETED) {
      await this.bookingRepository.completeActiveAssignment(conn, booking.id);
    }

    if (toStatus === BOOKING_STATUS.CANCELLED) {
      await this.bookingRepository.clearAssignmentOnCancel(
        conn,
        booking.id,
        actor.id,
        actor.role === ROLES.CUSTOMER ? 'CUSTOMER_CANCELLED' : 'ADMIN_CANCELLED',
      );
    }

    await this.bookingRepository.insertStatusLog(conn, booking.id, {
      fromStatus,
      toStatus,
      changedByUserId: actor.id,
      changedByRole: actor.role,
      reason: input.reason ?? null,
      memo: input.memo ?? null,
    });

    await this.bookingRepository.insertActivityLog(conn, booking.id, {
      activityType: ACTIVITY_BY_STATUS[toStatus] ?? 'BOOKING_STATUS_CHANGED',
      actorUserId: actor.id,
      actorRole: actor.role,
      description: `Booking status changed from ${fromStatus} to ${toStatus}`,
      payload: this.buildActivityPayload(booking, fromStatus, toStatus, actor, {
        ...input,
        occurredAt,
      }),
    });

    const domainEvent = EVENT_BY_STATUS[toStatus];
    const eventPayload = this.buildEventPayload(booking, fromStatus, toStatus, actor, {
      ...input,
      occurredAt,
    });

    let outboxId = null;
    if (this.outboxRepository && domainEvent && isNotificationOutboxEvent(domainEvent)) {
      outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
        aggregateId: booking.id,
        eventType: domainEvent,
        payload: eventPayload,
      });
    }

    return {
      result: this.buildBookingResult(booking, toStatus),
      domainEvent,
      eventPayload,
      outboxId,
      releasedDriverUserId:
        toStatus === BOOKING_STATUS.CANCELLED ? releasedDriverUserId : null,
    };
  }

  async transition(bookingNumber, input, actor, options = {}) {
    const conn = await this.pool.getConnection();
    let transition;

    try {
      await conn.beginTransaction();
      transition = await this.transitionInTransaction(
        conn,
        bookingNumber,
        input,
        actor,
        options,
      );
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    await this.dispatchOutboxAfterCommit(transition.outboxId);
    this.emitDomainEvent(transition.domainEvent, transition.eventPayload);
    if (transition.releasedDriverUserId) {
      emitDriverAssignmentReleased(transition.releasedDriverUserId, {
        bookingNumber,
        reason: 'CANCELLED',
      });
    }
    return transition.result;
  }

  async cancelByCustomer(bookingNumber, input = {}, authUser = null, options = {}) {
    const conn = await this.pool.getConnection();
    let transition;
    let actor = null;

    try {
      await conn.beginTransaction();

      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        bookingNumber,
      );
      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      actor = await this.resolveCustomerOrGuestActor(conn, booking, authUser, input.guestAccessToken);

      // Re-read path goes through transitionInTransaction which locks again — reuse current conn flow:
      // We already hold the lock; call validate + mutate inline via transitionInTransaction after unlock is wrong.
      // Release and re-enter is messy. Instead inline cancel using already-locked booking:
      const fromStatus = booking.status;
      const toStatus = BOOKING_STATUS.CANCELLED;

      if (fromStatus === toStatus) {
        await conn.commit();
        const evaluation = this.evaluateCancellation(booking, options.nowMs);
        return this.buildBookingResult(booking, toStatus, true, {
          canCancel: false,
          cancellationDeadline: evaluation.cancellationDeadline,
          cancellationBlockedReason: evaluation.cancellationBlockedReason,
        });
      }

      this.assertCustomerCancellationAllowed(booking, options.nowMs);
      this.validateTransition(fromStatus, toStatus, ROLES.CUSTOMER);

      const occurredAt = new Date().toISOString();
      const releasedDriverUserId = booking.driver_user_id ?? null;

      await this.bookingRepository.updateStatus(conn, booking.id, toStatus, actor.id, {
        cancellationReason: input.reason ?? input.memo ?? 'CUSTOMER_CANCELLED',
      });
      await this.bookingRepository.clearAssignmentOnCancel(
        conn,
        booking.id,
        actor.id,
        'CUSTOMER_CANCELLED',
      );
      await this.bookingRepository.insertStatusLog(conn, booking.id, {
        fromStatus,
        toStatus,
        changedByUserId: actor.id,
        changedByRole: actor.role,
        reason: input.reason ?? 'CUSTOMER_CANCELLED',
        memo: input.memo ?? null,
      });
      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: ACTIVITY_BY_STATUS[toStatus],
        actorUserId: actor.id,
        actorRole: actor.role,
        description: `Booking status changed from ${fromStatus} to ${toStatus}`,
        payload: this.buildActivityPayload(booking, fromStatus, toStatus, actor, {
          reason: input.reason ?? 'CUSTOMER_CANCELLED',
          memo: input.memo ?? null,
          occurredAt,
        }),
      });

      const domainEvent = EVENT_BY_STATUS[toStatus];
      const eventPayload = this.buildEventPayload(booking, fromStatus, toStatus, actor, {
        reason: input.reason ?? 'CUSTOMER_CANCELLED',
        occurredAt,
      });

      let outboxId = null;
      if (this.outboxRepository && domainEvent && isNotificationOutboxEvent(domainEvent)) {
        outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
          aggregateId: booking.id,
          eventType: domainEvent,
          payload: eventPayload,
        });
      }

      await conn.commit();

      transition = {
        result: this.buildBookingResult(booking, toStatus, false, {
          canCancel: false,
          cancellationDeadline: this.evaluateCancellation(
            { ...booking, status: toStatus },
            options.nowMs,
          ).cancellationDeadline,
          cancellationBlockedReason: 'ALREADY_CANCELLED',
        }),
        domainEvent,
        eventPayload,
        outboxId,
        releasedDriverUserId,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    await this.dispatchOutboxAfterCommit(transition.outboxId);
    if (transition.releasedDriverUserId) {
      emitDriverAssignmentReleased(transition.releasedDriverUserId, {
        bookingNumber,
        reason: 'CANCELLED',
      });
    }
    return transition.result;
  }

  async resolveCustomerOrGuestActor(conn, booking, authUser, guestAccessToken) {
    if (
      authUser?.role === ROLES.CUSTOMER
      && booking.customer_user_id
      && booking.customer_user_id === authUser.id
    ) {
      return { id: authUser.id, role: ROLES.CUSTOMER };
    }

    if ([ROLES.ADMIN, ROLES.SUPER_ADMIN].includes(authUser?.role)) {
      // Admin should use status transition, not customer cancel endpoint.
      throw new AppError('Use admin status transition for force cancel', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.FORBIDDEN,
      });
    }

    const token = String(guestAccessToken ?? '').trim();
    if (!token) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }

    const guestToken = await this.bookingRepository.findActiveGuestTokenForBooking(
      conn,
      booking.id,
      hashToken(token),
    );
    if (!guestToken) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }

    return {
      id: booking.customer_user_id ?? null,
      role: ROLES.CUSTOMER,
    };
  }
}

module.exports = BookingStatusService;
