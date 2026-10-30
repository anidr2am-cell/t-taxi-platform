const database = require('../config/database');
const NOTIFICATION_CHANNELS = require('../constants/notificationChannels');
const DELIVERY_STATUS = require('../constants/notificationDeliveryStatus');
const { customerEmailSlot, CUSTOMER_EMAIL_TYPES, CUSTOMER_EMAIL_LIMIT } = require('../policies/notificationEmail.policy');
const { canRecoverAttempt } = require('../policies/emailAttempt.policy');
const { randomUUID } = require('node:crypto');
const { formatServiceDateTimeIso } = require('../utils/serviceDateTime.util');

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

  async insertEmailOnly(conn,data) {
    const id=await this.insert(conn,data);
    await conn.query("UPDATE notifications SET channel='EMAIL' WHERE id=?",[id]);
    return id;
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

  async updateDeliveryStatus(conn, deliveryId, status, lastError = null, deliveredAt = null, incrementAttempt = true) {
    await conn.query(
      `
        UPDATE notification_deliveries
        SET delivery_status = ?,
            attempt_count = attempt_count + ?,
            last_error = ?,
            delivered_at = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [status, incrementAttempt ? 1 : 0, lastError, deliveredAt, deliveryId],
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
            WHEN n.recipient_type = 'USER' AND (n.type = 'TRIP_ENDED' OR (n.type = 'TRIP_COMPLETED' AND JSON_UNQUOTE(JSON_EXTRACT(n.payload, '$.tripEndedDirectly')) = 'true')) AND u.role = 'CUSTOMER'
              THEN COALESCE(NULLIF(TRIM(b.customer_email), ''), u.email)
            WHEN n.recipient_type = 'USER' THEN u.email
            WHEN n.recipient_type = 'GUEST_BOOKING' THEN b.customer_email
            ELSE NULL
          END AS recipient_email,
          u.locale AS recipient_locale,
          u.role AS recipient_user_role,
          b.metadata AS booking_metadata,
          b.total_amount AS booking_total_amount,
          b.payment_method AS booking_payment_method,
          b.payment_status AS booking_payment_status,
          b.currency AS booking_currency,
          vt.code AS booking_vehicle_type,
          ba.id AS email_assignment_id,
          dr.name AS assigned_driver_name,
          dv.model_name AS assigned_vehicle_model,
          dv.color AS assigned_vehicle_color,
          dv.plate_number AS assigned_vehicle_plate,
          avt.code AS assigned_vehicle_type,
          b.booking_number,
          b.scheduled_pickup_at,
          b.origin_address,
          b.destination_address,
          b.status AS booking_status
        FROM notifications n
        LEFT JOIN users u ON u.id = n.user_id AND u.deleted_at IS NULL
        LEFT JOIN bookings b ON b.id = n.booking_id AND b.deleted_at IS NULL
        LEFT JOIN vehicle_types vt ON vt.id = b.vehicle_type_id
        LEFT JOIN booking_driver_assignments ba ON ba.id = (
          SELECT x.id FROM booking_driver_assignments x
          WHERE x.booking_id=b.id AND x.is_active=1 AND x.deleted_at IS NULL ORDER BY x.id DESC LIMIT 1
        )
        LEFT JOIN drivers dr ON dr.id=ba.driver_id AND dr.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.id=ba.driver_vehicle_id AND dv.deleted_at IS NULL
        LEFT JOIN vehicle_types avt ON avt.id=dv.vehicle_type_id AND avt.deleted_at IS NULL
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

  async claimCustomerEmail(notification, delivery, recovery = null) {
    if (!notification.booking_id) return { allowed: false, error: 'EMAIL_POLICY_BOOKING_REQUIRED' };
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const [bookings] = await conn.query('SELECT id, metadata FROM bookings WHERE id = ? AND deleted_at IS NULL FOR UPDATE', [notification.booking_id]);
      if (!bookings.length) {
        await conn.commit();
        return { allowed: false, error: 'EMAIL_POLICY_BOOKING_REQUIRED' };
      }
      if(notification.type==='DRIVER_ASSIGNED') {
        // Recheck the current assignment under the booking lock before reserving
        // SMTP. Never send a stale assignment after release/completion/reassignment.
        const [[assignment]]=await conn.query(`SELECT ba.id FROM booking_driver_assignments ba
          JOIN bookings b ON b.id=ba.booking_id JOIN drivers d ON d.id=ba.driver_id AND d.deleted_at IS NULL
          WHERE ba.booking_id=? AND ba.is_active=1 AND ba.deleted_at IS NULL
          AND b.status IN ('DRIVER_ASSIGNED','ON_ROUTE','DRIVER_ARRIVED','PICKED_UP')
          ORDER BY ba.id DESC LIMIT 1`,[notification.booking_id]);
        if(!assignment || Number(assignment.id)!==Number(notification.email_assignment_id)) {
          await conn.commit();return {allowed:false,error:'EMAIL_POLICY_ASSIGNMENT_CHANGED'};
        }
      }
      let receiptMetadata=bookings[0].metadata;
      if(typeof receiptMetadata==='string'){try{receiptMetadata=JSON.parse(receiptMetadata)}catch{receiptMetadata={}}}
      if(receiptMetadata?.adminReceiptEmail?.notificationId && Number(receiptMetadata.adminReceiptEmail.notificationId)!==Number(notification.id)) {
        await conn.commit();return {allowed:false,error:'EMAIL_POLICY_SUPERSEDED_BY_ADMIN_RECEIPT'};
      }
      const [[current]] = await conn.query('SELECT delivery_status, attempt_count, last_error FROM notification_deliveries WHERE id = ? FOR UPDATE', [delivery.id]);
      if (!current || ['DELIVERED', 'SKIPPED'].includes(current.delivery_status)
        || (!recovery && current.last_error?.startsWith('PERMANENT_EMAIL_'))) {
        await conn.commit();
        return { alreadyProcessed: true };
      }
      let previousEnvelope = null;
      if (recovery) {
        const [[attempt]] = await conn.query('SELECT * FROM notification_email_attempts WHERE delivery_id = ? ORDER BY id DESC LIMIT 1 FOR UPDATE', [delivery.id]);
        const [[review]] = await conn.query("SELECT COUNT(*) AS n FROM notification_email_reviews WHERE delivery_id = ? AND action = 'ACCEPTED_CONFIRMED'", [delivery.id]);
        if (!attempt || Number(attempt.id) !== recovery.expectedAttemptId || !canRecoverAttempt(attempt) || !attempt.envelope_encrypted || Number(review.n)) {
          await conn.commit();
          return { allowed: false, error: 'EMAIL_RECOVERY_NOT_PROVEN' };
        }
        previousEnvelope = attempt.envelope_encrypted;
      }
      // Count historical sends too, including other customer event types. Failed
      // attempts may have been accepted by SMTP; count conservatively, not twice.
      const [history] = await conn.query(`SELECT n.type FROM notification_deliveries d
        JOIN notifications n ON n.id = d.notification_id LEFT JOIN users u ON u.id = n.user_id
        WHERE n.booking_id = ? AND d.channel = 'EMAIL' AND d.id <> ?
          AND COALESCE(n.audience_role, IF(n.recipient_type = 'GUEST_BOOKING', 'CUSTOMER', u.role)) = 'CUSTOMER'
          AND (d.delivery_status = 'DELIVERED' OR d.last_error LIKE 'PERMANENT_EMAIL_%'
            OR EXISTS (SELECT 1 FROM notification_email_reviews hr WHERE hr.delivery_id=d.id AND hr.action='ACCEPTED_CONFIRMED')
            OR (d.attempt_count > 0 AND d.delivery_status <> 'SKIPPED'
              AND COALESCE(d.last_error, '') <> 'PERMANENT_INVALID_RECIPIENT'))`, [notification.booking_id, recovery ? delivery.id : 0]);
      let error = history.length >= CUSTOMER_EMAIL_LIMIT ? 'EMAIL_POLICY_BOOKING_LIMIT' : null;
      if (history.some((row) => customerEmailSlot(row.type) === customerEmailSlot(notification.type))) {
        error = 'EMAIL_POLICY_SLOT_ALREADY_USED';
      }
      if (notification.type === 'BOOKING_CANCELLED') {
        const [[started]] = await conn.query(`SELECT COUNT(*) AS n FROM booking_status_logs
          WHERE booking_id = ? AND (from_status IN ('ON_ROUTE','DRIVER_ARRIVED','PICKED_UP','SETTLEMENT_PENDING','COMPLETED')
            OR to_status IN ('ON_ROUTE','DRIVER_ARRIVED','PICKED_UP','SETTLEMENT_PENDING','COMPLETED'))`, [notification.booking_id]);
        if (Number(started.n)) error = 'EMAIL_POLICY_CANCELLATION_AFTER_START';
      }
      if (error) {
        await conn.commit();
        return { allowed: false, error };
      }
      if (recovery) {
        await conn.query(`INSERT INTO notification_email_reviews (delivery_id,attempt_id,action,actor_user_id,reason)
          VALUES (?,?,'RETRY_APPROVED',?,?)`, [delivery.id, recovery.expectedAttemptId, recovery.actorUserId, recovery.reason]);
      }
      const traceId = randomUUID();
      const messageId = `<trider-email-${delivery.id}@trider.taxi>`;
      const [insert] = await conn.query('INSERT INTO notification_email_attempts (delivery_id,trace_id,message_id,envelope_encrypted) VALUES (?,?,?,?)', [delivery.id, traceId, messageId, previousEnvelope]);
      await conn.query(`UPDATE notification_deliveries SET attempt_count = attempt_count + 1,
        last_error = 'PERMANENT_EMAIL_SEND_RESERVED', updated_at = CURRENT_TIMESTAMP WHERE id = ?`, [delivery.id]);
      await conn.commit();
      return { allowed: true, attempt: { id: insert.insertId, traceId, messageId, envelope: previousEnvelope } };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally { conn.release(); }
  }

  async finishEmailAttempt(conn, attemptId, evidence) {
    await conn.query(`UPDATE notification_email_attempts SET outcome = ?,provider_message_id = ?,
      error_code = ?,smtp_command = ?,smtp_response_code = ?,finished_at = CURRENT_TIMESTAMP WHERE id = ? AND outcome = 'SENDING'`,
    [evidence.outcome, evidence.providerMessageId || null, evidence.errorCode ? String(evidence.errorCode).slice(0,80) : null,
      evidence.smtpCommand || null, evidence.smtpResponseCode || null, attemptId]);
  }

  async saveEmailEnvelope(attemptId, encrypted) {
    const [result] = await this.pool.query("UPDATE notification_email_attempts SET envelope_encrypted=? WHERE id=? AND outcome='SENDING'", [encrypted, attemptId]);
    if (result.affectedRows !== 1) throw new Error('EMAIL_SNAPSHOT_NOT_SAVED');
  }

  async findEmailDelivery(id) {
    const [[row]] = await this.pool.query("SELECT id,notification_id,channel,delivery_status,attempt_count,last_error FROM notification_deliveries WHERE id=? AND channel='EMAIL'", [id]);
    return row || null;
  }

  async emailReviewRows(includeHandled = false, page = 1) {
    const [rows] = await this.pool.query(`SELECT d.id deliveryId,n.id notificationId,n.type notificationType,
      n.booking_id bookingId,b.booking_number bookingNumber,d.delivery_status deliveryStatus,
      (JSON_UNQUOTE(JSON_EXTRACT(n.payload, '$.tripEndedDirectly')) = 'true') directTripEnded,
      d.last_error lastError,d.attempt_count attemptCount,d.updated_at updatedAt,
      a.id attemptId,a.trace_id traceId,a.message_id messageId,a.provider_message_id providerMessageId,
      a.outcome,a.error_code errorCode,a.smtp_command smtpCommand,a.smtp_response_code smtpResponseCode,
      (a.envelope_encrypted IS NOT NULL) hasEnvelope,
      a.started_at startedAt,a.finished_at finishedAt,
      (SELECT COUNT(*) FROM notification_email_reviews ar WHERE ar.delivery_id=d.id AND ar.action='ACCEPTED_CONFIRMED') acceptedConfirmed,
      (a.outcome='SENDING' AND a.started_at < NOW()-INTERVAL 10 MINUTE) stale,
      r.action reviewAction,r.reason reviewReason,r.actor_user_id reviewerId,r.created_at reviewedAt
      FROM notification_deliveries d JOIN notifications n ON n.id=d.notification_id
      LEFT JOIN bookings b ON b.id=n.booking_id
      LEFT JOIN notification_email_attempts a ON a.id=(SELECT MAX(a2.id) FROM notification_email_attempts a2 WHERE a2.delivery_id=d.id)
      LEFT JOIN notification_email_reviews r ON r.id=(SELECT MAX(r2.id) FROM notification_email_reviews r2 WHERE r2.delivery_id=d.id)
      WHERE d.channel='EMAIL' AND n.deleted_at IS NULL
        AND (n.audience_role='CUSTOMER' OR n.recipient_type='GUEST_BOOKING')
        AND (a.outcome IN ('UNKNOWN','NOT_ACCEPTED')
          ${includeHandled ? "OR (a.outcome='ACCEPTED' AND r.id IS NOT NULL)" : ''}
          OR (a.outcome='SENDING' AND a.started_at<NOW()-INTERVAL 10 MINUTE)
          OR (a.id IS NULL AND d.last_error LIKE 'PERMANENT_EMAIL_%'
            AND (d.delivery_status='FAILED' OR d.updated_at<NOW()-INTERVAL 10 MINUTE)))
        ${includeHandled ? '' : "AND (r.id IS NULL OR r.action IN ('KEEP_BLOCKED','RETRY_APPROVED'))"}
      ORDER BY d.id DESC LIMIT 100 OFFSET ?`, [(page - 1) * 100]);
    return rows.map((r) => ({ ...r, updatedAt: formatServiceDateTimeIso(r.updatedAt), startedAt: formatServiceDateTimeIso(r.startedAt),
      finishedAt: formatServiceDateTimeIso(r.finishedAt), reviewedAt: formatServiceDateTimeIso(r.reviewedAt),
      recoverable: canRecoverAttempt({ outcome: r.outcome,
      error_code: r.errorCode, smtp_command: r.smtpCommand, smtp_response_code: r.smtpResponseCode })
      && Boolean(r.hasEnvelope) && CUSTOMER_EMAIL_TYPES.has(r.notificationType)
      && (r.notificationType!=='TRIP_COMPLETED' || Number(r.directTripEnded)===1)
      && !['DELIVERED','SKIPPED'].includes(r.deliveryStatus) && !Number(r.acceptedConfirmed) }));
  }

  async emailAttemptHistory(deliveryId) {
    const [attempts] = await this.pool.query('SELECT id,delivery_id,trace_id,message_id,provider_message_id,outcome,error_code,smtp_command,smtp_response_code,started_at,finished_at FROM notification_email_attempts WHERE delivery_id=? ORDER BY id', [deliveryId]);
    const [reviews] = await this.pool.query('SELECT * FROM notification_email_reviews WHERE delivery_id=? ORDER BY id', [deliveryId]);
    return { attempts: attempts.map((a) => ({ ...a, started_at: formatServiceDateTimeIso(a.started_at), finished_at: formatServiceDateTimeIso(a.finished_at) })),
      reviews: reviews.map((r) => ({ ...r, created_at: formatServiceDateTimeIso(r.created_at) })) };
  }

  async addEmailReview(deliveryId, actorUserId, action, reason) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const [[row]] = await conn.query(`SELECT n.booking_id FROM notification_deliveries d JOIN notifications n ON n.id=d.notification_id
        WHERE d.id=? AND d.channel='EMAIL' AND (n.audience_role='CUSTOMER' OR n.recipient_type='GUEST_BOOKING')`, [deliveryId]);
      if (!row?.booking_id) { await conn.commit(); return false; }
      await conn.query('SELECT id FROM bookings WHERE id=? FOR UPDATE', [row.booking_id]);
      await conn.query('SELECT id FROM notification_deliveries WHERE id=? FOR UPDATE', [deliveryId]);
      await conn.query(`INSERT INTO notification_email_reviews (delivery_id,attempt_id,action,actor_user_id,reason)
        VALUES (?,(SELECT MAX(id) FROM notification_email_attempts WHERE delivery_id=?),?,?,?)`,
      [deliveryId,deliveryId,action,actorUserId,reason]);
      await conn.commit();
      return true;
    } catch (err) { await conn.rollback(); throw err; }
    finally { conn.release(); }
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

  async findRecoverableNotificationIds(limit = 100) {
    const boundedLimit = Math.min(Math.max(Number(limit) || 100, 1), 500);
    const [rows] = await this.pool.query(
      `
        SELECT DISTINCT n.id
        FROM notifications n
        INNER JOIN notification_deliveries d ON d.notification_id = n.id
        WHERE n.deleted_at IS NULL
          AND d.delivery_status IN ('PENDING', 'FAILED')
          AND d.attempt_count < 3
          AND (d.last_error IS NULL OR d.last_error NOT LIKE 'PERMANENT\\_%')
        ORDER BY n.id ASC
        LIMIT ?
      `,
      [boundedLimit],
    );
    return rows.map((row) => Number(row.id)).filter(Number.isInteger);
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
    const where = ['deleted_at IS NULL', "NOT (channel='EMAIL' AND COALESCE(JSON_UNQUOTE(JSON_EXTRACT(payload,'$.adminReceipt')),'false')='true')"];
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
