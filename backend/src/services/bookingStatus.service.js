const AppError = require('../utils/AppError');
const { randomUUID } = require('node:crypto');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const ROLES = require('../constants/roles');
const { appEvents, EVENTS } = require('../events');
const { isNotificationOutboxEvent } = require('../utils/outboxPayload.util');

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
    [BOOKING_STATUS.CANCELLED]: [ROLES.ADMIN, ROLES.SUPER_ADMIN],
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

  buildBookingResult(booking, status, idempotent = false) {
    return {
      id: booking.id,
      bookingNumber: booking.booking_number,
      status,
      paymentStatus: booking.payment_status,
      paymentMethod: booking.payment_method,
      totalAmount: Number(booking.total_amount),
      currency: booking.currency,
      idempotent,
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
      };
    }

    this.validateTransition(fromStatus, toStatus, actor.role);
    const occurredAt = new Date().toISOString();

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

    if (toStatus === BOOKING_STATUS.COMPLETED) {
      await this.bookingRepository.completeActiveAssignment(conn, booking.id);
    }

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
    };
  }

  async transition(bookingNumber, input, actor) {
    const conn = await this.pool.getConnection();
    let transition;

    try {
      await conn.beginTransaction();
      transition = await this.transitionInTransaction(conn, bookingNumber, input, actor);
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    await this.dispatchOutboxAfterCommit(transition.outboxId);
    this.emitDomainEvent(transition.domainEvent, transition.eventPayload);
    return transition.result;
  }
}

module.exports = BookingStatusService;
