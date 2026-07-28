const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const NOTIFICATION_TYPES = require('../constants/notificationTypes');
const { ADMIN_RELEASED_REASON_CODE } = require('../constants/bookingAssignmentRelease.constants');
const {
  emitDriverCallClaimed,
  emitDriverCallAvailable,
  emitDriverAssignmentReleased,
  emitDriverUrgentCallNew,
} = require('../socket/realtime');
const logger = require('../utils/logger');

class BookingAssignmentReopenService {
  constructor(
    bookingRepository,
    driverRepository,
    notificationService = null,
    chatRepository = null,
    commissionSettlementService = null,
    urgentNegotiationRepository = null,
  ) {
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.notificationService = notificationService;
    this.chatRepository = chatRepository;
    this.commissionSettlementService = commissionSettlementService;
    this.urgentNegotiationRepository = urgentNegotiationRepository;
  }

  async listEligibleDriversForReopenedBooking(conn, {
    booking,
    releasedAssignmentId,
  }) {
    const candidates = await this.driverRepository.listEligibleForOpenBooking(
      conn,
      booking.vehicle_type_id,
      { excludeReleasedBookingId: booking.id },
    );
    const drivers = [];
    for (const candidate of candidates) {
      const blocked = this.commissionSettlementService
        ? await this.commissionSettlementService.driverHasBlockingSettlement(candidate.id)
        : false;
      if (!blocked) drivers.push(candidate);
    }
    return drivers;
  }

  mapEligibleDriversToTargets(drivers) {
    return drivers.map((driver) => ({
      driverId: driver.id,
      userId: driver.user_id,
    }));
  }

  buildDriverNotificationPayload(bookingNumber, payload, targetScreen) {
    return {
      ...payload,
      bookingNumber,
      targetScreen,
    };
  }

  async dispatchOpenCallNotifications({
    drivers,
    bookingId,
    bookingNumber,
    openCallPayload,
    releasedAssignmentId,
  }) {
    if (!this.notificationService || !drivers.length) {
      return;
    }

    const payload = this.buildDriverNotificationPayload(
      bookingNumber,
      openCallPayload,
      'open_calls',
    );
    for (const driver of drivers) {
      try {
        await this.notificationService.sendDirectNotification({
          recipientUserId: driver.user_id,
          recipientDriverId: driver.id,
          bookingId,
          notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
          payload,
          idempotencyKey: `driver-call-reopened:${bookingId}:${driver.id}:${releasedAssignmentId}`,
          eventName: 'driver.call.available',
        });
      } catch (err) {
        logger.warn('Reopened open call notification failed', {
          bookingId,
          driverId: driver.id,
          error: err.message,
        });
      }
    }
  }

  async dispatchUrgentCallNotifications({
    drivers,
    bookingId,
    bookingNumber,
    urgentPayload,
    releasedAssignmentId,
  }) {
    if (!this.notificationService || !drivers.length) {
      return;
    }

    const payload = this.buildDriverNotificationPayload(
      bookingNumber,
      urgentPayload,
      'urgent_calls',
    );
    for (const driver of drivers) {
      try {
        await this.notificationService.sendDirectNotification({
          recipientUserId: driver.user_id,
          recipientDriverId: driver.id,
          bookingId,
          notificationType: NOTIFICATION_TYPES.DRIVER_URGENT_CALL_NEW,
          payload,
          idempotencyKey: `driver-urgent-call-reopened:${bookingId}:${driver.id}:${releasedAssignmentId}`,
          eventName: 'driver.urgent-call.new',
        });
      } catch (err) {
        logger.warn('Reopened urgent call notification failed', {
          bookingId,
          driverId: driver.id,
          error: err.message,
        });
      }
    }
  }

  async notifyEligibleDriversForReopenedBooking(conn, params) {
    const drivers = await this.listEligibleDriversForReopenedBooking(conn, params);
    return this.mapEligibleDriversToTargets(drivers);
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

  async restartUrgentNegotiationAfterRelease(conn, booking, evaluation) {
    if (!this.urgentNegotiationRepository) {
      throw new AppError('Urgent negotiation service is unavailable', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_FOUND,
      });
    }

    const negotiationId = await this.urgentNegotiationRepository.insertNegotiation(conn, {
      bookingId: booking.id,
    });
    await this.bookingRepository.updateUrgentNegotiationId(
      conn,
      booking.id,
      negotiationId,
    );

    return {
      bookingNumber: booking.booking_number,
      negotiationId,
      attemptCount: 0,
      minRequiredEtaMinutes: null,
      reassignmentPriority: evaluation.reassignmentPriority,
      releasedByDriver: evaluation.releasedByDriver ?? false,
    };
  }

  async reopenAssignedBookingInTransaction(conn, params) {
    const {
      booking,
      bookingNumber,
      activeAssignment,
      actorUserId,
      actorRole,
      assignmentReleaseMarker,
      assignmentSocketReasonCode,
      statusLogMemo,
      activityType,
      activityDescription,
      activityPayload,
      reassignmentPriority = 'NORMAL',
      releasedByDriver = false,
      releasedDriverUserId,
      mapOpenCall,
      urgentEvaluation = null,
    } = params;

    const deactivated = await this.bookingRepository.deactivateAssignment(
      conn,
      activeAssignment.id,
      assignmentReleaseMarker,
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
      actorUserId,
    );
    await this.bookingRepository.insertStatusLog(conn, booking.id, {
      fromStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
      toStatus: BOOKING_STATUS.OPEN,
      changedByUserId: actorUserId,
      changedByRole: actorRole,
      reason: assignmentReleaseMarker,
      memo: statusLogMemo,
    });
    await this.bookingRepository.insertActivityLog(conn, booking.id, {
      activityType,
      actorUserId,
      actorRole,
      description: activityDescription,
      payload: activityPayload,
    });
    await this.deactivateReleasedDriverChatParticipant(
      conn,
      booking,
      releasedDriverUserId,
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

    const openCallPayload = {
      ...mapOpenCall(openRow),
      reassignmentPriority,
      releasedByDriver,
    };

    let urgentRebroadcastPayload = null;
    let openCallTargets = [];
    const notificationDrivers = await this.listEligibleDriversForReopenedBooking(conn, {
      booking,
      releasedAssignmentId: activeAssignment.id,
    });

    if (Number(booking.is_urgent_request)) {
      urgentRebroadcastPayload = await this.restartUrgentNegotiationAfterRelease(
        conn,
        { ...booking, booking_number: bookingNumber },
        {
          reassignmentPriority,
          releasedByDriver,
          ...urgentEvaluation,
        },
      );
    } else {
      openCallTargets = this.mapEligibleDriversToTargets(notificationDrivers);
    }

    return {
      bookingId: booking.id,
      bookingNumber,
      releasedAssignmentId: activeAssignment.id,
      assignmentSocketReasonCode,
      reassignmentPriority,
      openCallPayload,
      openCallTargets,
      notificationDrivers,
      urgentRebroadcastPayload,
    };
  }

  async emitReopenEvents({
    bookingId,
    bookingNumber,
    releasedDriverUserId,
    releasedAssignmentId,
    assignmentSocketReasonCode,
    reassignmentPriority,
    openCallPayload,
    openCallTargets = [],
    notificationDrivers = [],
    urgentRebroadcastPayload = null,
  }) {
    if (releasedDriverUserId) {
      emitDriverAssignmentReleased(releasedDriverUserId, {
        bookingNumber,
        status: BOOKING_STATUS.OPEN,
        reason: assignmentSocketReasonCode,
        reasonCode: assignmentSocketReasonCode,
        bookingStatus: BOOKING_STATUS.OPEN,
        reassignmentPriority,
        releasedAt: new Date().toISOString(),
      });

      if (this.notificationService && assignmentSocketReasonCode === ADMIN_RELEASED_REASON_CODE) {
        try {
          await this.notificationService.sendDirectNotification({
            recipientUserId: releasedDriverUserId,
            bookingId,
            notificationType: NOTIFICATION_TYPES.ADMIN_RELEASED,
            payload: {
              bookingNumber,
              targetScreen: 'assignments',
            },
            idempotencyKey: `admin-released:${bookingId}:${releasedDriverUserId}:${releasedAssignmentId ?? 'none'}`,
            eventName: 'driver.assignment.released',
          });
        } catch (err) {
          logger.warn('Admin released notification failed', {
            bookingId,
            releasedDriverUserId,
            error: err.message,
          });
        }
      }
    }

    if (urgentRebroadcastPayload) {
      emitDriverUrgentCallNew(urgentRebroadcastPayload);
      await this.dispatchUrgentCallNotifications({
        drivers: notificationDrivers,
        bookingId,
        bookingNumber,
        urgentPayload: urgentRebroadcastPayload,
        releasedAssignmentId,
      });
      return;
    }

    emitDriverCallClaimed({ bookingNumber });
    for (const target of openCallTargets) {
      emitDriverCallAvailable(target.userId, openCallPayload);
    }
    await this.dispatchOpenCallNotifications({
      drivers: notificationDrivers,
      bookingId,
      bookingNumber,
      openCallPayload,
      releasedAssignmentId,
    });
  }
}

module.exports = BookingAssignmentReopenService;
