const database = require('../config/database');
const { OUTBOX_STATUS, NOTIFICATION_AGGREGATE_TYPE } = require('../constants/outboxStatus');
const { sanitizeOutboxPayload } = require('../utils/outboxPayload.util');

class OutboxRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  parsePayload(row) {
    if (!row?.payload) return {};
    if (typeof row.payload === 'string') {
      try {
        return JSON.parse(row.payload);
      } catch {
        return {};
      }
    }
    return row.payload;
  }

  async insertNotificationEvent(conn, { aggregateId, eventType, payload }) {
    const sanitized = sanitizeOutboxPayload(payload);
    const [result] = await conn.query(
      `
        INSERT INTO outbox_events (
          aggregate_type,
          aggregate_id,
          event_type,
          payload,
          status,
          scheduled_at
        ) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      `,
      [
        NOTIFICATION_AGGREGATE_TYPE,
        aggregateId,
        eventType,
        JSON.stringify(sanitized),
        OUTBOX_STATUS.PENDING,
      ],
    );
    return result.insertId;
  }

  async findById(id, conn = null) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT
          id,
          aggregate_type,
          aggregate_id,
          event_type,
          payload,
          status,
          retry_count,
          max_retries,
          scheduled_at,
          processed_at,
          error_message,
          created_at,
          updated_at
        FROM outbox_events
        WHERE id = ?
        LIMIT 1
      `,
      [id],
    );
    const row = rows[0];
    if (!row) return null;
    row.payload = this.parsePayload(row);
    return row;
  }

  async findByIdForUpdate(conn, id) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          aggregate_type,
          aggregate_id,
          event_type,
          payload,
          status,
          retry_count,
          max_retries,
          scheduled_at,
          processed_at,
          error_message
        FROM outbox_events
        WHERE id = ?
        LIMIT 1
        FOR UPDATE
      `,
      [id],
    );
    const row = rows[0];
    if (!row) return null;
    row.payload = this.parsePayload(row);
    return row;
  }

  async claimPendingBatch(conn, limit) {
    const [rows] = await conn.query(
      `
        SELECT id
        FROM outbox_events
        WHERE status IN (?, ?)
          AND retry_count < max_retries
          AND scheduled_at <= CURRENT_TIMESTAMP
        ORDER BY scheduled_at ASC, id ASC
        LIMIT ?
        FOR UPDATE SKIP LOCKED
      `,
      [OUTBOX_STATUS.PENDING, OUTBOX_STATUS.FAILED, limit],
    );

    if (!rows.length) return [];

    const ids = rows.map((row) => row.id);
    await conn.query(
      `
        UPDATE outbox_events
        SET status = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id IN (?)
      `,
      [OUTBOX_STATUS.PROCESSING, ids],
    );

    const [claimed] = await conn.query(
      `
        SELECT
          id,
          aggregate_type,
          aggregate_id,
          event_type,
          payload,
          status,
          retry_count,
          max_retries
        FROM outbox_events
        WHERE id IN (?)
      `,
      [ids],
    );

    return claimed.map((row) => {
      row.payload = this.parsePayload(row);
      return row;
    });
  }

  async claimById(id) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const row = await this.findByIdForUpdate(conn, id);
      if (!row) {
        await conn.commit();
        return null;
      }
      if (row.status === OUTBOX_STATUS.COMPLETED) {
        await conn.commit();
        return null;
      }
      if (
        row.status !== OUTBOX_STATUS.PENDING
        && row.status !== OUTBOX_STATUS.FAILED
        && row.status !== OUTBOX_STATUS.PROCESSING
      ) {
        await conn.commit();
        return null;
      }
      await conn.query(
        `
          UPDATE outbox_events
          SET status = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [OUTBOX_STATUS.PROCESSING, id],
      );
      await conn.commit();
      row.status = OUTBOX_STATUS.PROCESSING;
      return row;
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async markCompleted(id) {
    await this.pool.query(
      `
        UPDATE outbox_events
        SET status = ?,
            processed_at = CURRENT_TIMESTAMP,
            error_message = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [OUTBOX_STATUS.COMPLETED, id],
    );
  }

  async markFailed(id, errorMessage) {
    const sanitizedError = String(errorMessage ?? 'Processing failed').slice(0, 500);
    await this.pool.query(
      `
        UPDATE outbox_events
        SET retry_count = retry_count + 1,
            error_message = ?,
            status = CASE
              WHEN retry_count + 1 >= max_retries THEN ?
              ELSE ?
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [
        sanitizedError,
        OUTBOX_STATUS.FAILED,
        OUTBOX_STATUS.PENDING,
        id,
      ],
    );
  }
}

module.exports = OutboxRepository;
