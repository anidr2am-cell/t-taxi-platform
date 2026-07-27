const AppError = require('../utils/AppError');
const { randomUUID } = require('node:crypto');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const NOTIFICATION_TYPES = require('../constants/notificationTypes');
const RECIPIENT_TYPES = require('../constants/notificationRecipientTypes');
const {
  emitDriverCallClaimed,
  emitDriverCallAvailable,
  emitDriverAssignmentReleased,
  emitDriverUrgentCallNew,
} = require('../socket/realtime');

class BookingAssignmentReopenService {
  constructor(
    bookingRepository,
    driverRepository,
    notificationRepository = null,
    chatRepository = null,
    commissionSettlementService = null,
    urgentNegotiationRepository = null,
  ) {
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.notificationRepository = notificationRepository;
    this.chatRepository = chatRepository;
    this.commissionSettlementService = commissionSettlementService;
    this.urgentNegotiationRepository = urgentNegotiationRepository;
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
    for (const candidate of candidates) {
      const blocked = this.commissionSettlementService
        ? await this.commissionSettlementService.driverHasBlockingSettlement(candidate.id)
        : false;
      if (!blocked) drivers.push(candidate);
    }

    const eventId = randomUUID();
    if (this.notificationRepository) {
      for (const driver of drivers) {
        await this.notificationRepository.insert(conn, {
          recipientType: RECIPIENT_TYPES.USER,
          userId: driver.user_id,
          recipientDriverId: driver.id,
          bookingId: booking.id,
          audienceRole: 'DRIVER',
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
      openCallTargets = await this.notifyEligibleDriversForReopenedBooking(conn, {
        booking,
        openCallPayload,
        releasedAssignmentId: activeAssignment.id,
      });
    }

    return {
      bookingNumber,
      assignmentSocketReasonCode,
      reassignmentPriority,
      openCallPayload,
      openCallTargets,
      urgentRebroadcastPayload,
    };
  }

  emitReopenEvents({
    bookingNumber,
    releasedDriverUserId,
    assignmentSocketReasonCode,
    reassignmentPriority,
    openCallPayload,
    openCallTargets = [],
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
    }

    if (urgentRebroadcastPayload) {
      emitDriverUrgentCallNew(urgentRebroadcastPayload);
      return;
    }

    emitDriverCallClaimed({ bookingNumber });
    for (const target of openCallTargets) {
      emitDriverCallAvailable(target.userId, openCallPayload);
    }
  }
}

module.exports = BookingAssignmentReopenService;
