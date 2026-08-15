class BookingIdempotencyRepository {
  async findByKeyForUpdate(conn, idempotencyKey) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          idempotency_key,
          request_hash,
          booking_id,
          response_status,
          response_payload,
          status,
          expires_at
        FROM booking_idempotency_keys
        WHERE idempotency_key = ?
          AND expires_at > UTC_TIMESTAMP()
        FOR UPDATE
      `,
      [idempotencyKey],
    );
    return rows[0] ?? null;
  }

  async insertPending(conn, { idempotencyKey, requestHash, expiresAt }) {
    const [result] = await conn.query(
      `
        INSERT INTO booking_idempotency_keys (
          idempotency_key,
          request_hash,
          status,
          expires_at
        ) VALUES (?, ?, 'PENDING', ?)
      `,
      [idempotencyKey, requestHash, expiresAt],
    );
    return result.insertId;
  }

  async markCompleted(conn, { idempotencyKey, bookingId, responseStatus, responsePayload }) {
    await conn.query(
      `
        UPDATE booking_idempotency_keys
        SET
          booking_id = ?,
          response_status = ?,
          response_payload = ?,
          status = 'COMPLETED',
          updated_at = UTC_TIMESTAMP()
        WHERE idempotency_key = ?
          AND status = 'PENDING'
      `,
      [bookingId, responseStatus, JSON.stringify(responsePayload), idempotencyKey],
    );
  }

  async deletePending(conn, idempotencyKey) {
    await conn.query(
      `
        DELETE FROM booking_idempotency_keys
        WHERE idempotency_key = ?
          AND status = 'PENDING'
      `,
      [idempotencyKey],
    );
  }

  async deleteExpiredBatch(conn, batchSize) {
    const [result] = await conn.query(
      `
        DELETE FROM booking_idempotency_keys
        WHERE expires_at < UTC_TIMESTAMP()
        ORDER BY expires_at ASC
        LIMIT ?
      `,
      [batchSize],
    );
    return result.affectedRows ?? 0;
  }
}

module.exports = BookingIdempotencyRepository;
