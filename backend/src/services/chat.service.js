const { randomUUID } = require("node:crypto");
const AppError = require("../utils/AppError");
const HTTP_STATUS = require("../constants/httpStatus");
const ERROR_CODES = require("../constants/errorCodes");
const BOOKING_STATUS = require("../constants/reservationStatus");
const ROLES = require("../constants/roles");
const { EVENTS } = require("../events");
const { hashToken } = require("../utils/tokenHash.util");

const MAX_MESSAGE_LENGTH = 2000;
const READ_ONLY_STATUSES = new Set([
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.NO_SHOW,
]);

class ChatService {
  constructor(
    pool,
    chatRepository,
    bookingRepository,
    driverRepository,
    userRepository,
    outboxRepository,
    outboxProcessor,
  ) {
    this.pool = pool;
    this.chatRepository = chatRepository;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.userRepository = userRepository;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
  }

  formatDateTime(date) {
    return date.toISOString().slice(0, 19).replace("T", " ");
  }

  isSendingAllowed(bookingStatus) {
    return !READ_ONLY_STATUSES.has(bookingStatus);
  }

  mapParticipantRole(userRole) {
    if (userRole === ROLES.DRIVER) return "DRIVER";
    if (userRole === ROLES.ADMIN || userRole === ROLES.SUPER_ADMIN)
      return "ADMIN";
    return "CUSTOMER";
  }

  previewText(text, max = 120) {
    const value = String(text ?? "").trim();
    if (value.length <= max) return value;
    return `${value.slice(0, max - 1)}…`;
  }

  mapMessage(row, participant, readByCurrentUser = false) {
    return {
      messageId: row.id,
      senderType: row.sender_role,
      senderDisplayName: row.sender_name,
      text: row.content,
      createdAt: row.created_at,
      readByCurrentUser,
      clientMessageId: row.client_message_id ?? undefined,
    };
  }

  async ensureRoom(conn, booking) {
    let room = await this.chatRepository.findRoomByBookingIdForUpdate(
      conn,
      booking.id,
    );
    if (room) return room;
    const roomCode = `CHAT-${booking.booking_number}`;
    try {
      const roomId = await this.chatRepository.insertRoom(
        conn,
        booking.id,
        roomCode,
      );
      room = {
        id: roomId,
        booking_id: booking.id,
        room_code: roomCode,
        is_active: 1,
        created_at: new Date(),
      };
    } catch (err) {
      if (err.code === "ER_DUP_ENTRY") {
        room = await this.chatRepository.findRoomByBookingId(conn, booking.id);
      } else {
        throw err;
      }
    }
    return room;
  }

  async ensureCustomerParticipant(
    conn,
    room,
    booking,
    authUser,
    guestAccessToken,
  ) {
    if (
      authUser?.role === ROLES.CUSTOMER &&
      booking.customer_user_id === authUser.id
    ) {
      let participant = await this.chatRepository.findParticipant(
        conn,
        room.id,
        "CUSTOMER",
        authUser.id,
      );
      if (!participant) {
        const participantId = await this.chatRepository.insertParticipant(
          conn,
          room.id,
          {
            userId: authUser.id,
            participantRole: "CUSTOMER",
            displayName: booking.customer_name ?? "Customer",
          },
        );
        participant = await this.chatRepository.findParticipantById(
          conn,
          participantId,
        );
      }
      return { participant, canSend: this.isSendingAllowed(booking.status) };
    }

    const token = String(guestAccessToken ?? "").trim();
    if (!token) {
      throw new AppError("Chat is not accessible", {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.CHAT_NOT_ACCESSIBLE,
      });
    }
    const guestToken =
      await this.bookingRepository.findActiveGuestTokenForBooking(
        conn,
        booking.id,
        hashToken(token),
      );
    if (!guestToken) {
      throw new AppError("Chat is not accessible", {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.CHAT_NOT_ACCESSIBLE,
      });
    }

    let participant = await this.chatRepository.findGuestParticipant(
      conn,
      room.id,
    );
    if (!participant) {
      const participantId = await this.chatRepository.insertParticipant(
        conn,
        room.id,
        {
          userId: null,
          participantRole: "CUSTOMER",
          displayName: booking.customer_name ?? "Guest",
        },
      );
      participant = await this.chatRepository.findParticipantById(
        conn,
        participantId,
      );
    }
    return { participant, canSend: this.isSendingAllowed(booking.status) };
  }

  async ensureDriverParticipant(conn, room, booking, driverUserId) {
    const active =
      await this.bookingRepository.findActiveDriverBookingByNumberForUpdate(
        conn,
        driverUserId,
        booking.booking_number,
      );
    if (!active) {
      throw new AppError("Chat is not accessible", {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.CHAT_NOT_ACCESSIBLE,
      });
    }
    const driver = await this.driverRepository.findByUserId(driverUserId);
    let participant = await this.chatRepository.findParticipant(
      conn,
      room.id,
      "DRIVER",
      driverUserId,
    );
    if (!participant) {
      const participantId = await this.chatRepository.insertParticipant(
        conn,
        room.id,
        {
          userId: driverUserId,
          participantRole: "DRIVER",
          displayName: driver?.name ?? "Driver",
        },
      );
      participant = await this.chatRepository.findParticipantById(
        conn,
        participantId,
      );
    }
    return {
      participant,
      canSend: this.isSendingAllowed(booking.status),
    };
  }

  async ensureAdminParticipant(conn, room, booking, authUser) {
    const profile = await this.userRepository.findById(authUser.id);
    let participant = await this.chatRepository.findParticipant(
      conn,
      room.id,
      "ADMIN",
      authUser.id,
    );
    if (!participant) {
      const participantId = await this.chatRepository.insertParticipant(
        conn,
        room.id,
        {
          userId: authUser.id,
          participantRole: "ADMIN",
          displayName: profile?.name ?? profile?.email ?? "Admin",
        },
      );
      participant = await this.chatRepository.findParticipantById(
        conn,
        participantId,
      );
    }
    return {
      participant,
      canSend: this.isSendingAllowed(booking.status),
    };
  }

  async syncAssignedParticipants(
    conn,
    { booking, driver, adminUser, previousDriverUserId = null },
  ) {
    const room = await this.ensureRoom(conn, booking);
    const driverUserId = Number(driver.user_id);

    if (
      previousDriverUserId != null &&
      Number(previousDriverUserId) !== driverUserId
    ) {
      await this.chatRepository.deactivateParticipant(
        conn,
        room.id,
        "DRIVER",
        previousDriverUserId,
      );
    }

    let driverParticipant = await this.chatRepository.findParticipant(
      conn,
      room.id,
      "DRIVER",
      driverUserId,
    );
    if (!driverParticipant) {
      const displayName = driver.name ?? "Driver";
      const reactivated = await this.chatRepository.reactivateParticipant(
        conn,
        room.id,
        "DRIVER",
        driverUserId,
        displayName,
      );
      if (reactivated) {
        driverParticipant = await this.chatRepository.findParticipant(
          conn,
          room.id,
          "DRIVER",
          driverUserId,
        );
      } else {
        const participantId = await this.chatRepository.insertParticipant(
          conn,
          room.id,
          {
            userId: driverUserId,
            participantRole: "DRIVER",
            displayName,
          },
        );
        driverParticipant = await this.chatRepository.findParticipantById(
          conn,
          participantId,
        );
      }
    }

    let adminParticipant = await this.chatRepository.findParticipant(
      conn,
      room.id,
      "ADMIN",
      adminUser.id,
    );
    if (!adminParticipant) {
      const admin = await this.userRepository.findById(adminUser.id);
      const participantId = await this.chatRepository.insertParticipant(
        conn,
        room.id,
        {
          userId: adminUser.id,
          participantRole: "ADMIN",
          displayName:
            admin?.name ?? admin?.email ?? adminUser.email ?? "Admin",
        },
      );
      adminParticipant = await this.chatRepository.findParticipantById(
        conn,
        participantId,
      );
    }

    return {
      room,
      driverParticipant,
      adminParticipant,
    };
  }

  async resolveAccess(conn, bookingNumber, authUser, guestAccessToken) {
    const booking = await this.bookingRepository.findByBookingNumberForUpdate(
      conn,
      bookingNumber,
    );
    if (!booking) {
      throw new AppError("Booking not found", {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }
    const room = await this.ensureRoom(conn, booking);

    if (authUser?.role === ROLES.DRIVER) {
      const access = await this.ensureDriverParticipant(
        conn,
        room,
        booking,
        authUser.id,
      );
      return { booking, room, ...access, actorRole: ROLES.DRIVER };
    }
    if (
      authUser?.role === ROLES.ADMIN ||
      authUser?.role === ROLES.SUPER_ADMIN
    ) {
      const access = await this.ensureAdminParticipant(
        conn,
        room,
        booking,
        authUser,
      );
      return { booking, room, ...access, actorRole: authUser.role };
    }
    const access = await this.ensureCustomerParticipant(
      conn,
      room,
      booking,
      authUser,
      guestAccessToken,
    );
    return { booking, room, ...access, actorRole: ROLES.CUSTOMER };
  }

  async buildRoomResponse(conn, context) {
    const participants = await this.chatRepository.listParticipants(
      conn,
      context.room.id,
    );
    const unreadCount = await this.chatRepository.countUnreadForParticipant(
      conn,
      context.room.id,
      context.participant,
    );
    const lastMessage = await this.chatRepository.findLastMessage(
      conn,
      context.room.id,
    );
    return {
      roomId: context.room.id,
      bookingNumber: context.booking.booking_number,
      bookingStatus: context.booking.status,
      sendingAllowed: context.canSend,
      participants: participants.map((p) => ({
        participantType: p.participant_role,
        displayName: p.display_name,
      })),
      unreadCount,
      lastMessage: lastMessage
        ? {
            messageId: lastMessage.id,
            text: this.previewText(lastMessage.content),
            createdAt: lastMessage.created_at,
          }
        : null,
      createdAt: context.room.created_at,
    };
  }

  async getRoom(bookingNumber, authUser, guestAccessToken) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const context = await this.resolveAccess(
        conn,
        bookingNumber,
        authUser,
        guestAccessToken,
      );
      await conn.commit();
      return this.buildRoomResponse(conn, context);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async listMessages(bookingNumber, authUser, guestAccessToken, query = {}) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const context = await this.resolveAccess(
        conn,
        bookingNumber,
        authUser,
        guestAccessToken,
      );
      const rows = await this.chatRepository.listMessages(
        conn,
        context.room.id,
        {
          cursor: query.cursor ? Number(query.cursor) : null,
          limit: query.limit ?? query.page_size ?? 50,
        },
      );
      await conn.commit();
      const items = rows.map((row) => {
        const readByCurrentUser = context.participant.last_read_at
          ? new Date(row.created_at) <=
            new Date(context.participant.last_read_at)
          : false;
        return this.mapMessage(row, context.participant, readByCurrentUser);
      });
      return {
        items,
        ordering: "newest_first",
        nextCursor: items.length ? items[items.length - 1].messageId : null,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  validateMessageText(text) {
    const trimmed = String(text ?? "").trim();
    if (!trimmed) {
      throw new AppError("Message cannot be empty", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.CHAT_MESSAGE_EMPTY,
      });
    }
    if (trimmed.length > MAX_MESSAGE_LENGTH) {
      throw new AppError("Message is too long", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.CHAT_MESSAGE_TOO_LONG,
      });
    }
    return trimmed;
  }

  async queueChatNotifications(
    conn,
    { booking, messageId, clientMessageId, senderParticipantId, participants },
  ) {
    if (!this.outboxRepository) return [];
    const outboxIds = [];
    for (const recipient of participants) {
      if (recipient.id === senderParticipantId) continue;
      const eventId = `${clientMessageId}:chat:${recipient.id}`;
      const payload = {
        eventId,
        eventName: EVENTS.CHAT_MESSAGE_SENT,
        bookingId: booking.id,
        bookingNumber: booking.booking_number,
        messageId,
        recipientParticipantId: recipient.id,
        recipientUserId: recipient.user_id ?? null,
        recipientRole: recipient.participant_role,
        customerUserId: booking.customer_user_id ?? null,
      };
      const outboxId = await this.outboxRepository.insertNotificationEvent(
        conn,
        {
          aggregateId: booking.id,
          eventType: EVENTS.CHAT_MESSAGE_SENT,
          payload,
        },
      );
      outboxIds.push(outboxId);
    }
    return outboxIds;
  }

  async sendMessage(bookingNumber, authUser, guestAccessToken, input) {
    const text = this.validateMessageText(input.text);
    const clientMessageId = String(input.clientMessageId ?? "").trim();
    if (!clientMessageId) {
      throw new AppError("Validation failed", {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const conn = await this.pool.getConnection();
    let outboxIds = [];
    try {
      await conn.beginTransaction();
      const context = await this.resolveAccess(
        conn,
        bookingNumber,
        authUser,
        guestAccessToken,
      );
      if (!context.canSend) {
        throw new AppError("Chat is read-only for this booking", {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.CHAT_READ_ONLY,
        });
      }

      const existing = await this.chatRepository.findMessageByClientId(
        conn,
        context.room.id,
        context.participant.id,
        clientMessageId,
      );
      if (existing) {
        await conn.commit();
        return {
          message: this.mapMessage(existing, context.participant, true),
          roomId: context.room.id,
          broadcast: false,
        };
      }

      const messageId = await this.chatRepository.insertMessage(conn, {
        chatRoomId: context.room.id,
        senderUserId: context.participant.user_id,
        senderParticipantId: context.participant.id,
        senderRole: context.participant.participant_role,
        senderName: context.participant.display_name,
        content: text,
        clientMessageId,
      });

      const participants = await this.chatRepository.listParticipants(
        conn,
        context.room.id,
      );
      outboxIds = await this.queueChatNotifications(conn, {
        booking: context.booking,
        messageId,
        clientMessageId,
        senderParticipantId: context.participant.id,
        participants,
      });

      const saved = await this.chatRepository.findMessageById(
        conn,
        messageId,
        context.room.id,
      );
      await conn.commit();

      if (this.outboxProcessor && outboxIds.length) {
        await this.outboxProcessor.dispatchOutboxIds(outboxIds);
      }

      return {
        message: this.mapMessage(saved, context.participant, true),
        roomId: context.room.id,
        roomCode: context.room.room_code,
        broadcast: true,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async markRead(bookingNumber, authUser, guestAccessToken, input = {}) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const context = await this.resolveAccess(
        conn,
        bookingNumber,
        authUser,
        guestAccessToken,
      );
      const upToMessageId = Number(input.upToMessageId ?? input.messageId);
      if (!upToMessageId) {
        throw new AppError("Validation failed", {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      const target = await this.chatRepository.findMessageById(
        conn,
        upToMessageId,
        context.room.id,
      );
      if (!target) {
        throw new AppError("Message not found", {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.CHAT_MESSAGE_NOT_FOUND,
        });
      }
      const readAt = this.formatDateTime(new Date(target.created_at));
      await this.chatRepository.updateParticipantLastRead(
        conn,
        context.participant.id,
        readAt,
      );
      await this.chatRepository.insertMessageRead(
        conn,
        target.id,
        context.participant.id,
      );
      const unreadCount = await this.chatRepository.countUnreadForParticipant(
        conn,
        context.room.id,
        { ...context.participant, last_read_at: readAt },
      );
      await conn.commit();
      return {
        upToMessageId: target.id,
        unreadCount,
        roomId: context.room.id,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async listAdminChats(authUser, query = {}) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(
      Math.max(Number(query.limit ?? query.page_size) || 20, 1),
      100,
    );
    const offset = (page - 1) * limit;
    const conn = await this.pool.getConnection();
    try {
      const rows = await this.chatRepository.listAdminChatSummaries(
        conn,
        authUser.id,
        {
          search: query.search ?? query.q ?? null,
          unreadOnly: query.unreadOnly === true || query.unread_only === "true",
          limit,
          offset,
        },
      );
      const total = await this.chatRepository.countAdminChatSummaries(
        conn,
        authUser.id,
        {
          search: query.search ?? query.q ?? null,
          unreadOnly: query.unreadOnly === true || query.unread_only === "true",
        },
      );
      const items = [];
      for (const row of rows) {
        let unreadCount = 0;
        if (row.admin_participant_id) {
          unreadCount = await this.chatRepository.countUnreadForParticipant(
            conn,
            row.room_id,
            {
              id: row.admin_participant_id,
              last_read_at: row.admin_last_read_at,
            },
          );
        } else if (row.last_message_id) {
          unreadCount = 1;
        }
        items.push({
          bookingNumber: row.booking_number,
          bookingStatus: row.booking_status,
          customerDisplayName: row.customer_name,
          driverDisplayName: row.driver_name ?? null,
          lastMessageText: row.last_message_text
            ? this.previewText(row.last_message_text)
            : null,
          lastMessageAt: row.last_message_at,
          unreadCount,
          roomStatus: row.is_active ? "ACTIVE" : "INACTIVE",
        });
      }
      return { page, pageSize: limit, total, items };
    } finally {
      conn.release();
    }
  }

  async getAdminRoom(bookingNumber, authUser) {
    return this.getRoom(bookingNumber, authUser, null);
  }

  async listAdminMessages(bookingNumber, authUser, query) {
    return this.listMessages(bookingNumber, authUser, null, query);
  }

  async sendAdminMessage(bookingNumber, authUser, input) {
    return this.sendMessage(bookingNumber, authUser, null, input);
  }

  async markAdminRead(bookingNumber, authUser, input) {
    return this.markRead(bookingNumber, authUser, null, input);
  }

  async isDriverAuthorizedForBooking(bookingNumber, driverUserId) {
    const conn = await this.pool.getConnection();
    try {
      const active =
        await this.bookingRepository.findActiveDriverBookingByNumberForUpdate(
          conn,
          driverUserId,
          bookingNumber,
        );
      return Boolean(active);
    } finally {
      conn.release();
    }
  }
}

module.exports = ChatService;
