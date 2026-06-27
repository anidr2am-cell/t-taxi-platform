const { createHash } = require('node:crypto');
const logger = require('../utils/logger');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');
const NOTIFICATION_TYPES = require('../constants/notificationTypes');
const NOTIFICATION_CHANNELS = require('../constants/notificationChannels');
const DELIVERY_STATUS = require('../constants/notificationDeliveryStatus');
const RECIPIENT_TYPES = require('../constants/notificationRecipientTypes');
const { EVENTS } = require('../events');
const { createDeliveryAdapters } = require('./notificationDelivery.adapters');

const FORBIDDEN_PAYLOAD_KEYS = new Set([
  'guestAccessToken',
  'guest_access_token',
  'token',
  'token_hash',
  'qrToken',
  'qr_token',
  'password',
  'accessToken',
  'refreshToken',
  'commission_receipt_file_id',
  'filePath',
  'file_path',
]);

const CONTENT = {
  [NOTIFICATION_TYPES.BOOKING_CREATED]: {
    title: 'Booking created',
    body: 'Your booking has been created.',
  },
  [NOTIFICATION_TYPES.BOOKING_CONFIRMED]: {
    title: 'Booking confirmed',
    body: 'Your booking has been confirmed.',
  },
  [NOTIFICATION_TYPES.DRIVER_ASSIGNED]: {
    title: 'Driver assigned',
    body: 'A driver has been assigned to your trip.',
  },
  [NOTIFICATION_TYPES.DRIVER_ARRIVED]: {
    title: 'Driver arrived',
    body: 'Your driver has arrived at the pickup point.',
  },
  [NOTIFICATION_TYPES.TRIP_PICKED_UP]: {
    title: 'Trip started',
    body: 'Your trip has started.',
  },
  [NOTIFICATION_TYPES.TRIP_COMPLETED]: {
    title: 'Trip completed',
    body: 'Your trip has been completed.',
  },
  [NOTIFICATION_TYPES.REVIEW_REQUESTED]: {
    title: 'Rate your trip',
    body: 'Please share feedback about your completed trip.',
  },
  [NOTIFICATION_TYPES.COMMISSION_REQUIRED]: {
    title: 'Commission payment required',
    body: 'Please submit your commission receipt for the completed trip.',
  },
  [NOTIFICATION_TYPES.RECEIPT_SUBMITTED]: {
    title: 'Receipt submitted',
    body: 'A driver submitted a commission receipt for review.',
  },
  [NOTIFICATION_TYPES.RECEIPT_REJECTED]: {
    title: 'Receipt rejected',
    body: 'Your commission receipt was rejected. Please resubmit.',
  },
  [NOTIFICATION_TYPES.SETTLEMENT_APPROVED]: {
    title: 'Settlement approved',
    body: 'Your commission settlement has been approved.',
  },
  [NOTIFICATION_TYPES.DRIVER_REASSIGNED]: {
    title: 'Booking reassigned',
    body: 'You have been assigned to a new booking.',
  },
  [NOTIFICATION_TYPES.REVIEW_SUBMITTED]: {
    title: 'Review submitted',
    body: 'A customer submitted a review for a completed trip.',
  },
  [NOTIFICATION_TYPES.CHAT_MESSAGE_RECEIVED]: {
    title: 'New chat message',
    body: 'You have a new message about your booking.',
  },
};

class NotificationService {
  constructor(
    pool,
    notificationRepository,
    userRepository,
    bookingRepository,
    driverRepository,
    bookingService,
    adapters = null,
  ) {
    this.pool = pool;
    this.notificationRepository = notificationRepository;
    this.userRepository = userRepository;
    this.bookingRepository = bookingRepository;
    this.driverRepository = driverRepository;
    this.bookingService = bookingService;
    this.adapters = adapters ?? createDeliveryAdapters();
  }

  parsePagination(query) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit ?? query.page_size) || 20;
    const safeLimit = Math.min(Math.max(limit, 1), 100);
    const offset = (Math.max(page, 1) - 1) * safeLimit;
    return { page: Math.max(page, 1), limit: safeLimit, offset };
  }

  parseListFilters(query) {
    const filters = {
      notificationType: query.notificationType || null,
      unreadOnly: query.unreadOnly === 'true' || query.unreadOnly === true,
      createdFrom: null,
      createdTo: null,
    };
    if (query.createdFrom) filters.createdFrom = `${query.createdFrom} 00:00:00`;
    if (query.createdTo) {
      const end = new Date(`${query.createdTo}T00:00:00`);
      end.setDate(end.getDate() + 1);
      filters.createdTo = end.toISOString().slice(0, 19).replace('T', ' ');
    }
    return filters;
  }

  sanitizePayload(payload) {
    const safe = {};
    for (const [key, value] of Object.entries(payload ?? {})) {
      if (FORBIDDEN_PAYLOAD_KEYS.has(key)) continue;
      if (typeof value === 'string' && value.length > 200) continue;
      safe[key] = value;
    }
    return safe;
  }

  buildIdempotencyKey(eventId, notificationType, recipientKey) {
    const base = `${eventId}:${notificationType}:${recipientKey}`;
    if (base.length <= 128) return base;
    return createHash('sha256').update(base).digest('hex');
  }

  buildRecipientKey(spec) {
    if (spec.recipientType === RECIPIENT_TYPES.GUEST_BOOKING) {
      return `guest_booking:${spec.bookingId}`;
    }
    return `user:${spec.userId}`;
  }

  resolveContent(notificationType, bookingNumber) {
    const template = CONTENT[notificationType] ?? { title: 'Notification', body: 'You have a new notification.' };
    const suffix = bookingNumber ? ` (${bookingNumber})` : '';
    return {
      title: template.title,
      body: `${template.body}${suffix}`,
    };
  }

  async handleDomainEvent(eventName, payload) {
    const specs = await this.buildSpecsForEvent(eventName, payload);
    for (const spec of specs) {
      await this.createNotificationIdempotent(spec);
    }
  }

  async buildSpecsForEvent(eventName, payload) {
    const booking = payload.bookingId
      ? await this.bookingRepository.findById(payload.bookingId)
      : null;
    const bookingNumber = payload.bookingNumber ?? booking?.booking_number ?? null;
    const eventId = payload.eventId ?? this.fallbackEventId(eventName, payload);
    const specs = [];

    const customerUserId = payload.customerUserId ?? booking?.customer_user_id ?? null;
    const driverUserId = payload.driverUserId ?? booking?.driver_user_id ?? null;
    const driverId = payload.driverId ?? booking?.driver_id ?? null;

    const customerPayload = this.sanitizePayload({ bookingNumber });

    const addCustomer = (notificationType) => {
      if (customerUserId) {
        specs.push({
          eventId,
          eventName,
          notificationType,
          recipientType: RECIPIENT_TYPES.USER,
          userId: customerUserId,
          bookingId: payload.bookingId ?? booking?.id ?? null,
          audienceRole: ROLES.CUSTOMER,
          payload: customerPayload,
        });
      } else if (payload.bookingId || booking?.id) {
        specs.push({
          eventId,
          eventName,
          notificationType,
          recipientType: RECIPIENT_TYPES.GUEST_BOOKING,
          bookingId: payload.bookingId ?? booking.id,
          audienceRole: ROLES.CUSTOMER,
          payload: customerPayload,
        });
      }
    };

    const addDriver = (notificationType) => {
      if (!driverUserId) return;
      specs.push({
        eventId,
        eventName,
        notificationType,
        recipientType: RECIPIENT_TYPES.USER,
        userId: driverUserId,
        recipientDriverId: driverId,
        bookingId: payload.bookingId ?? booking?.id ?? null,
        audienceRole: ROLES.DRIVER,
        payload: customerPayload,
      });
    };

    const addAdmins = async (notificationType) => {
      const admins = await this.userRepository.findActiveByRoles([ROLES.ADMIN, ROLES.SUPER_ADMIN]);
      for (const admin of admins) {
        specs.push({
          eventId,
          eventName,
          notificationType,
          recipientType: RECIPIENT_TYPES.USER,
          userId: admin.id,
          bookingId: payload.bookingId ?? booking?.id ?? null,
          audienceRole: admin.role,
          payload: customerPayload,
        });
      }
    };

    switch (eventName) {
      case EVENTS.BOOKING_CREATED:
        addCustomer(NOTIFICATION_TYPES.BOOKING_CREATED);
        await addAdmins(NOTIFICATION_TYPES.BOOKING_CREATED);
        break;
      case EVENTS.BOOKING_CONFIRMED:
        addCustomer(NOTIFICATION_TYPES.BOOKING_CONFIRMED);
        break;
      case EVENTS.DRIVER_ASSIGNED:
        addCustomer(NOTIFICATION_TYPES.DRIVER_ASSIGNED);
        addDriver(NOTIFICATION_TYPES.DRIVER_ASSIGNED);
        break;
      case EVENTS.DRIVER_REASSIGNED:
        addDriver(NOTIFICATION_TYPES.DRIVER_REASSIGNED);
        break;
      case EVENTS.DRIVER_ARRIVED:
        addCustomer(NOTIFICATION_TYPES.DRIVER_ARRIVED);
        break;
      case EVENTS.TRIP_PICKED_UP:
        addCustomer(NOTIFICATION_TYPES.TRIP_PICKED_UP);
        break;
      case EVENTS.TRIP_COMPLETED:
        addCustomer(NOTIFICATION_TYPES.TRIP_COMPLETED);
        addCustomer(NOTIFICATION_TYPES.REVIEW_REQUESTED);
        break;
      case EVENTS.COMMISSION_REQUIRED:
        addDriver(NOTIFICATION_TYPES.COMMISSION_REQUIRED);
        break;
      case EVENTS.RECEIPT_SUBMITTED:
        await addAdmins(NOTIFICATION_TYPES.RECEIPT_SUBMITTED);
        break;
      case EVENTS.RECEIPT_REJECTED:
        addDriver(NOTIFICATION_TYPES.RECEIPT_REJECTED);
        break;
      case EVENTS.SETTLEMENT_APPROVED:
        addDriver(NOTIFICATION_TYPES.SETTLEMENT_APPROVED);
        break;
      case EVENTS.REVIEW_SUBMITTED:
        await addAdmins(NOTIFICATION_TYPES.REVIEW_SUBMITTED);
        break;
      case EVENTS.CHAT_MESSAGE_SENT: {
        const chatPayload = this.sanitizePayload({
          bookingNumber: payload.bookingNumber,
          messageId: payload.messageId,
        });
        if (payload.recipientUserId) {
          const audienceRole = payload.recipientRole === 'DRIVER'
            ? ROLES.DRIVER
            : payload.recipientRole === 'ADMIN'
              ? ROLES.ADMIN
              : ROLES.CUSTOMER;
          specs.push({
            eventId: payload.eventId,
            eventName,
            notificationType: NOTIFICATION_TYPES.CHAT_MESSAGE_RECEIVED,
            recipientType: RECIPIENT_TYPES.USER,
            userId: payload.recipientUserId,
            bookingId: payload.bookingId ?? null,
            audienceRole,
            payload: chatPayload,
          });
        } else if (payload.recipientRole === 'CUSTOMER' && payload.bookingId) {
          specs.push({
            eventId: payload.eventId,
            eventName,
            notificationType: NOTIFICATION_TYPES.CHAT_MESSAGE_RECEIVED,
            recipientType: RECIPIENT_TYPES.GUEST_BOOKING,
            bookingId: payload.bookingId,
            audienceRole: ROLES.CUSTOMER,
            payload: chatPayload,
          });
        }
        break;
      }
      default:
        break;
    }

    return specs;
  }

  fallbackEventId(eventName, payload) {
    const material = [
      eventName,
      payload.bookingId ?? '',
      payload.bookingNumber ?? '',
      payload.occurredAt ?? '',
      payload.actorUserId ?? '',
    ].join(':');
    return createHash('sha256').update(material).digest('hex').slice(0, 36);
  }

  async createNotificationIdempotent(spec) {
    const recipientKey = this.buildRecipientKey(spec);
    const idempotencyKey = this.buildIdempotencyKey(spec.eventId, spec.notificationType, recipientKey);
    const content = this.resolveContent(spec.notificationType, spec.payload?.bookingNumber);

    const conn = await this.pool.getConnection();
    let notificationId;
    let created = false;

    try {
      await conn.beginTransaction();
      const existing = await this.notificationRepository.findByIdempotencyKey(conn, idempotencyKey);
      if (existing) {
        notificationId = existing.id;
      } else {
        notificationId = await this.notificationRepository.insert(conn, {
          recipientType: spec.recipientType,
          userId: spec.userId ?? null,
          recipientDriverId: spec.recipientDriverId ?? null,
          bookingId: spec.bookingId ?? null,
          audienceRole: spec.audienceRole ?? null,
          eventId: spec.eventId,
          eventName: spec.eventName,
          idempotencyKey,
          notificationType: spec.notificationType,
          title: content.title,
          body: content.body,
          payload: spec.payload,
        });
        created = true;

        for (const channel of Object.values(NOTIFICATION_CHANNELS)) {
          const existingDelivery = await this.notificationRepository.findDeliveryByNotificationAndChannel(
            notificationId,
            channel,
            conn,
          );
          if (!existingDelivery) {
            await this.notificationRepository.insertDelivery(conn, {
              notificationId,
              channel,
              deliveryStatus: DELIVERY_STATUS.PENDING,
            });
          }
        }
      }

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        const row = await this.notificationRepository.findByIdempotencyKey(null, idempotencyKey);
        notificationId = row?.id;
      } else {
        throw err;
      }
    } finally {
      conn.release();
    }

    if (notificationId && created) {
      await this.processDeliveries(notificationId);
    }

    return { notificationId, created };
  }

  async processDeliveries(notificationId) {
    const notification = await this.notificationRepository.findById(notificationId);
    if (!notification) return;

    const deliveries = await this.notificationRepository.findDeliveriesByNotificationId(notificationId);
    const recipient = { userId: notification.user_id, bookingId: notification.booking_id };

    for (const delivery of deliveries) {
      if (delivery.delivery_status === DELIVERY_STATUS.DELIVERED
        || delivery.delivery_status === DELIVERY_STATUS.SKIPPED) {
        continue;
      }

      const adapter = this.adapters[delivery.channel];
      if (!adapter) continue;

      try {
        const result = await adapter.send(notification, recipient);
        const conn = await this.pool.getConnection();
        try {
          await conn.beginTransaction();
          const deliveredAt = result.status === DELIVERY_STATUS.DELIVERED
            ? new Date().toISOString().slice(0, 19).replace('T', ' ')
            : null;
          await this.notificationRepository.updateDeliveryStatus(
            conn,
            delivery.id,
            result.status,
            result.error ?? null,
            deliveredAt,
          );
          await conn.commit();
        } catch (err) {
          await conn.rollback();
          logger.warn('Notification delivery update failed', {
            notificationId,
            channel: delivery.channel,
            error: err.message,
          });
        } finally {
          conn.release();
        }
      } catch (err) {
        logger.warn('Notification adapter failed', {
          notificationId,
          channel: delivery.channel,
          error: err.message,
        });
      }
    }
  }

  mapListItem(row) {
    return {
      notificationId: row.id,
      notificationType: row.type,
      title: row.title,
      body: row.body,
      payload: this.sanitizePayload(row.payload ?? {}),
      read: row.read_at != null,
      readAt: row.read_at,
      createdAt: row.created_at,
    };
  }

  async listForUser(userId, audienceRole, query) {
    const pagination = this.parsePagination(query);
    const filters = {
      ...this.parseListFilters(query),
      userId,
      recipientType: RECIPIENT_TYPES.USER,
      audienceRole,
    };
    const total = await this.notificationRepository.countNotifications(filters);
    const rows = await this.notificationRepository.findNotifications(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total,
      items: rows.map((row) => this.mapListItem(row)),
    };
  }

  async listForGuestBooking(bookingId, query) {
    const pagination = this.parsePagination(query);
    const filters = {
      ...this.parseListFilters(query),
      bookingId,
      recipientType: RECIPIENT_TYPES.GUEST_BOOKING,
    };
    const total = await this.notificationRepository.countNotifications(filters);
    const rows = await this.notificationRepository.findNotifications(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total,
      items: rows.map((row) => this.mapListItem(row)),
    };
  }

  async unreadCountForUser(userId, audienceRole) {
    const count = await this.notificationRepository.countUnread({
      userId,
      recipientType: RECIPIENT_TYPES.USER,
      audienceRole,
    });
    return { unreadCount: count };
  }

  async unreadCountForGuestBooking(bookingId) {
    const count = await this.notificationRepository.countUnread({
      bookingId,
      recipientType: RECIPIENT_TYPES.GUEST_BOOKING,
    });
    return { unreadCount: count };
  }

  async markReadForUser(userId, audienceRole, notificationId) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const updated = await this.notificationRepository.markRead(conn, notificationId, {
        userId,
        recipientType: RECIPIENT_TYPES.USER,
        audienceRole,
      });
      if (!updated) {
        throw new AppError('Notification not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOTIFICATION_NOT_FOUND,
        });
      }
      await conn.commit();
      return { notificationId, read: true };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async markAllReadForUser(userId, audienceRole) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const count = await this.notificationRepository.markAllRead(conn, {
        userId,
        recipientType: RECIPIENT_TYPES.USER,
        audienceRole,
      });
      await conn.commit();
      return { updatedCount: count };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async markReadForGuestBooking(bookingId, notificationId) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const updated = await this.notificationRepository.markRead(conn, notificationId, {
        bookingId,
        recipientType: RECIPIENT_TYPES.GUEST_BOOKING,
      });
      if (!updated) {
        throw new AppError('Notification not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOTIFICATION_NOT_FOUND,
        });
      }
      await conn.commit();
      return { notificationId, read: true };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async getBookingNotifications(bookingNumber, authUser, guestAccessToken, query) {
    const normalized = this.bookingService.validateBookingNumber(bookingNumber);
    const booking = await this.bookingRepository.findByBookingNumber(normalized);
    if (!booking) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    if (authUser?.role === ROLES.CUSTOMER) {
      if (!booking.customer_user_id || booking.customer_user_id !== authUser.id) {
        throw new AppError('Booking is not accessible', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      }
      const pagination = this.parsePagination(query);
      const filters = {
        ...this.parseListFilters(query),
        userId: authUser.id,
        recipientType: RECIPIENT_TYPES.USER,
        audienceRole: ROLES.CUSTOMER,
        bookingId: booking.id,
      };
      const total = await this.notificationRepository.countNotifications(filters);
      const rows = await this.notificationRepository.findNotifications(filters, pagination);
      return {
        page: pagination.page,
        pageSize: pagination.limit,
        total,
        items: rows.map((row) => this.mapListItem(row)),
      };
    }

    const conn = await this.pool.getConnection();
    try {
      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );
    } finally {
      conn.release();
    }

    return this.listForGuestBooking(booking.id, query);
  }
}

module.exports = NotificationService;
