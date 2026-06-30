const database = require('../config/database');
const NOTIFICATION_CHANNELS = require('../constants/notificationChannels');
const DELIVERY_STATUS = require('../constants/notificationDeliveryStatus');

class NotificationRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  assertDeviceOwnership(data) {
    const hasUser = data.userId != null;
    const hasBooking = data.bookingId != null;
    if (hasUser === hasBooking) {
      throw new Error('notification_devices owner must be exactly one of user_id or booking_id');
    }
  }

  async findByIdempotencyKey(conn, idempotencyKey) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT id, user_id, booking_id, type, read_at, idempotency_key
        FROM notifications
        WHERE idempotency_key = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [idempotencyKey],
    );
    return rows[0] || null;
  }

  async insert(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO notifications (
          recipient_type,
          user_id,
          recipient_driver_id,
          booking_id,
          audience_role,
          event_id,
          event_name,
          idempotency_key,
          channel,
          type,
          title,
          body,
          payload,
          status,
          read_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'IN_APP', ?, ?, ?, ?, 'SENT', NULL)
      `,
      [
        data.recipientType,
        data.userId ?? null,
        data.recipientDriverId ?? null,
        data.bookingId ?? null,
        data.audienceRole ?? null,
        data.eventId ?? null,
        data.eventName ?? null,
        data.idempotencyKey,
        data.notificationType,
        data.title,
        data.body,
        JSON.stringify(data.payload ?? {}),
      ],
    );
    return result.insertId;
  }

  async insertDelivery(conn, data) {
    const [result] = await conn.query(
      `
        INSERT INTO notification_deliveries (
          notification_id,
          channel,
          delivery_status,
          attempt_count,
          last_error,
          delivered_at
        ) VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        data.notificationId,
        data.channel,
        data.deliveryStatus,
        data.attemptCount ?? 0,
        data.lastError ?? null,
        data.deliveredAt ?? null,
      ],
    );
    return result.insertId;
  }

  async findDeliveriesByNotificationId(notificationId, conn = null) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT id, notification_id, channel, delivery_status, attempt_count, last_error, delivered_at
        FROM notification_deliveries
        WHERE notification_id = ?
      `,
      [notificationId],
    );
    return rows;
  }

  async updateDeliveryStatus(conn, deliveryId, status, lastError = null, deliveredAt = null) {
    await conn.query(
      `
        UPDATE notification_deliveries
        SET delivery_status = ?,
            attempt_count = attempt_count + 1,
            last_error = ?,
            delivered_at = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [status, lastError, deliveredAt, deliveryId],
    );
  }

  async findById(notificationId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          n.id, n.recipient_type, n.user_id, n.recipient_driver_id, n.booking_id,
          n.audience_role, n.event_id, n.event_name, n.type, n.title, n.body, n.payload,
          n.read_at, n.created_at, n.updated_at,
          CASE
            WHEN n.recipient_type = 'USER' THEN u.email
            WHEN n.recipient_type = 'GUEST_BOOKING' THEN b.customer_email
            ELSE NULL
          END AS recipient_email,
          u.locale AS recipient_locale,
          b.booking_number,
          b.scheduled_pickup_at,
          b.origin_address,
          b.destination_address,
          b.status AS booking_status
        FROM notifications n
        LEFT JOIN users u ON u.id = n.user_id AND u.deleted_at IS NULL
        LEFT JOIN bookings b ON b.id = n.booking_id AND b.deleted_at IS NULL
        WHERE n.id = ? AND n.deleted_at IS NULL
        LIMIT 1
      `,
      [notificationId],
    );
    const row = rows[0];
    if (!row) return null;
    if (row.payload && typeof row.payload === 'string') {
      try { row.payload = JSON.parse(row.payload); } catch { row.payload = {}; }
    }
    return row;
  }

  async upsertDevice(conn, data) {
    this.assertDeviceOwnership(data);
    const executor = conn ?? this.pool;
    const [existing] = await executor.query(
      `
        SELECT id
        FROM notification_devices
        WHERE fcm_token_hash = ?
        LIMIT 1
      `,
      [data.tokenHash],
    );

    if (existing[0]) {
      await executor.query(
        `
          UPDATE notification_devices
          SET user_id = ?,
              booking_id = ?,
              platform = ?,
              fcm_token = ?,
              device_id = ?,
              device_name = ?,
              app_version = ?,
              is_active = 1,
              last_seen_at = CURRENT_TIMESTAMP,
              last_used_at = CURRENT_TIMESTAMP,
              deleted_at = NULL,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [
          data.userId ?? null,
          data.bookingId ?? null,
          data.platform,
          data.token,
          data.deviceId ?? null,
          data.deviceName ?? null,
          data.appVersion ?? null,
          existing[0].id,
        ],
      );
      return existing[0].id;
    }

    const [result] = await executor.query(
      `
        INSERT INTO notification_devices (
          user_id, booking_id, platform, fcm_token, fcm_token_hash,
          device_id, device_name, app_version, is_active, last_seen_at, last_used_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `,
      [
        data.userId ?? null,
        data.bookingId ?? null,
        data.platform,
        data.token,
        data.tokenHash,
        data.deviceId ?? null,
        data.deviceName ?? null,
        data.appVersion ?? null,
      ],
    );
    return result.insertId;
  }

  async listDevices(filters) {
    const where = ['is_active = 1', 'deleted_at IS NULL'];
    const params = [];
    if (filters.userId !== undefined) {
      where.push('user_id = ?');
      params.push(filters.userId);
    }
    if (filters.bookingId !== undefined) {
      where.push('booking_id = ?');
      params.push(filters.bookingId);
    }
    const [rows] = await this.pool.query(
      `
        SELECT id, user_id, booking_id, platform, fcm_token_hash, device_name,
               app_version, last_seen_at, created_at, updated_at
        FROM notification_devices
        WHERE ${where.join(' AND ')}
        ORDER BY last_seen_at DESC, id DESC
      `,
      params,
    );
    return rows;
  }

  async deactivateDevice(conn, filters) {
    const executor = conn ?? this.pool;
    const where = ['id = ?', 'is_active = 1', 'deleted_at IS NULL'];
    const params = [filters.deviceId];
    if (filters.userId !== undefined) {
      where.push('user_id = ?');
      params.push(filters.userId);
    }
    if (filters.bookingId !== undefined) {
      where.push('booking_id = ?');
      params.push(filters.bookingId);
    }
    const [result] = await executor.query(
      `
        UPDATE notification_devices
        SET is_active = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE ${where.join(' AND ')}
      `,
      params,
    );
    return result.affectedRows > 0;
  }

  async deactivateDeviceById(conn, deviceId) {
    const executor = conn ?? this.pool;
    await executor.query(
      `
        UPDATE notification_devices
        SET is_active = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [deviceId],
    );
  }

  async findActiveFcmDevicesForRecipient(recipient) {
    const where = ['is_active = 1', 'deleted_at IS NULL'];
    const params = [];
    if (recipient.userId) {
      where.push('user_id = ?');
      params.push(recipient.userId);
    } else if (recipient.bookingId) {
      where.push('booking_id = ?');
      params.push(recipient.bookingId);
    } else {
      return [];
    }
    const [rows] = await this.pool.query(
      `
        SELECT id, fcm_token
        FROM notification_devices
        WHERE ${where.join(' AND ')}
        ORDER BY last_seen_at DESC, id DESC
      `,
      params,
    );
    return rows;
  }

  buildDeliveryFilters(filters = {}) {
    const where = ['n.deleted_at IS NULL'];
    const params = [];

    if (filters.channel) {
      where.push('d.channel = ?');
      params.push(filters.channel);
    }
    if (filters.deliveryStatus) {
      where.push('d.delivery_status = ?');
      params.push(filters.deliveryStatus);
    }
    if (filters.notificationType) {
      where.push('n.type = ?');
      params.push(filters.notificationType);
    }
    if (filters.createdFrom) {
      where.push('d.created_at >= ?');
      params.push(filters.createdFrom);
    }
    if (filters.createdTo) {
      where.push('d.created_at < ?');
      params.push(filters.createdTo);
    }

    return { whereSql: where.join(' AND '), params };
  }

  async countDeliveries(filters) {
    const { whereSql, params } = this.buildDeliveryFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM notification_deliveries d
        INNER JOIN notifications n ON n.id = d.notification_id
        WHERE ${whereSql}
      `,
      params,
    );
    return Number(rows[0]?.total ?? 0);
  }

  async findDeliveries(filters, pagination) {
    const { whereSql, params } = this.buildDeliveryFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id,
          d.notification_id,
          d.channel,
          d.delivery_status,
          d.attempt_count,
          d.last_error,
          d.delivered_at,
          d.created_at,
          d.updated_at,
          n.type AS notification_type,
          n.event_name,
          n.audience_role,
          n.booking_id,
          b.booking_number
        FROM notification_deliveries d
        INNER JOIN notifications n ON n.id = d.notification_id
        LEFT JOIN bookings b ON b.id = n.booking_id AND b.deleted_at IS NULL
        WHERE ${whereSql}
        ORDER BY d.created_at DESC, d.id DESC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.limit, pagination.offset],
    );
    return rows;
  }

  buildListFilters(filters) {
    const where = ['deleted_at IS NULL'];
    const params = [];

    if (filters.userId) {
      where.push('user_id = ?');
      params.push(filters.userId);
    }
    if (filters.bookingId) {
      where.push('booking_id = ?');
      params.push(filters.bookingId);
    }
    if (filters.recipientType) {
      where.push('recipient_type = ?');
      params.push(filters.recipientType);
    }
    if (filters.audienceRole) {
      where.push('audience_role = ?');
      params.push(filters.audienceRole);
    }
    if (filters.unreadOnly) {
      where.push('read_at IS NULL');
    }
    if (filters.notificationType) {
      where.push('type = ?');
      params.push(filters.notificationType);
    }
    if (filters.createdFrom) {
      where.push('created_at >= ?');
      params.push(filters.createdFrom);
    }
    if (filters.createdTo) {
      where.push('created_at < ?');
      params.push(filters.createdTo);
    }

    return { whereSql: where.join(' AND '), params };
  }

  async countNotifications(filters) {
    const { whereSql, params } = this.buildListFilters(filters);
    const [rows] = await this.pool.query(
      `SELECT COUNT(*) AS total FROM notifications WHERE ${whereSql}`,
      params,
    );
    return Number(rows[0]?.total ?? 0);
  }

  async findNotifications(filters, pagination) {
    const { whereSql, params } = this.buildListFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT
          id, type, title, body, payload, read_at, created_at
        FROM notifications
        WHERE ${whereSql}
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.limit, pagination.offset],
    );
    return rows.map((row) => {
      if (row.payload && typeof row.payload === 'string') {
        try { row.payload = JSON.parse(row.payload); } catch { row.payload = {}; }
      }
      return row;
    });
  }

  async countUnread(filters) {
    const unreadFilters = { ...filters, unreadOnly: true };
    return this.countNotifications(unreadFilters);
  }

  async markRead(conn, notificationId, filters) {
    const { whereSql, params } = this.buildListFilters(filters);
    const [result] = await conn.query(
      `
        UPDATE notifications
        SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP),
            status = 'READ',
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND ${whereSql}
      `,
      [notificationId, ...params],
    );
    return result.affectedRows > 0;
  }

  async markAllRead(conn, filters) {
    const { whereSql, params } = this.buildListFilters(filters);
    const [result] = await conn.query(
      `
        UPDATE notifications
        SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP),
            status = 'READ',
            updated_at = CURRENT_TIMESTAMP
        WHERE read_at IS NULL AND ${whereSql}
      `,
      params,
    );
    return result.affectedRows;
  }

  async findDeliveryByNotificationAndChannel(notificationId, channel, conn = null) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT id, notification_id, channel, delivery_status
        FROM notification_deliveries
        WHERE notification_id = ? AND channel = ?
        LIMIT 1
      `,
      [notificationId, channel],
    );
    return rows[0] || null;
  }
}

module.exports = NotificationRepository;
