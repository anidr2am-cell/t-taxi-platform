const database = require('../config/database');
const NOTIFICATION_CHANNELS = require('../constants/notificationChannels');
const DELIVERY_STATUS = require('../constants/notificationDeliveryStatus');

class NotificationRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
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
          id, recipient_type, user_id, recipient_driver_id, booking_id,
          audience_role, event_id, event_name, type, title, body, payload,
          read_at, created_at, updated_at
        FROM notifications
        WHERE id = ? AND deleted_at IS NULL
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
