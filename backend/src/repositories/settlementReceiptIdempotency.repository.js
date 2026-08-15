class SettlementReceiptIdempotencyRepository {
  async findByScopeForUpdate(conn, { bookingId, driverUserId, idempotencyKey }) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          driver_user_id,
          idempotency_key,
          request_fingerprint,
          receipt_file_id,
          response_status,
          response_payload,
          status,
          expires_at
        FROM settlement_receipt_idempotency
        WHERE booking_id = ?
          AND driver_user_id = ?
          AND idempotency_key = ?
          AND expires_at > UTC_TIMESTAMP()
        FOR UPDATE
      `,
      [bookingId, driverUserId, idempotencyKey],
    );
    return rows[0] ?? null;
  }

  async insertPending(conn, {
    bookingId,
    driverUserId,
    idempotencyKey,
    requestFingerprint,
    expiresAt,
  }) {
    const [result] = await conn.query(
      `
        INSERT INTO settlement_receipt_idempotency (
          booking_id,
          driver_user_id,
          idempotency_key,
          request_fingerprint,
          status,
          expires_at
        ) VALUES (?, ?, ?, ?, 'PENDING', ?)
      `,
      [bookingId, driverUserId, idempotencyKey, requestFingerprint, expiresAt],
    );
    return result.insertId;
  }

  async markCompleted(conn, {
    bookingId,
    driverUserId,
    idempotencyKey,
    receiptFileId,
    responseStatus,
    responsePayload,
  }) {
    await conn.query(
      `
        UPDATE settlement_receipt_idempotency
        SET
          receipt_file_id = ?,
          response_status = ?,
          response_payload = ?,
          status = 'COMPLETED',
          updated_at = UTC_TIMESTAMP()
        WHERE booking_id = ?
          AND driver_user_id = ?
          AND idempotency_key = ?
          AND status = 'PENDING'
      `,
      [
        receiptFileId,
        responseStatus,
        JSON.stringify(responsePayload),
        bookingId,
        driverUserId,
        idempotencyKey,
      ],
    );
  }

  async deletePending(conn, { bookingId, driverUserId, idempotencyKey }) {
    await conn.query(
      `
        DELETE FROM settlement_receipt_idempotency
        WHERE booking_id = ?
          AND driver_user_id = ?
          AND idempotency_key = ?
          AND status = 'PENDING'
      `,
      [bookingId, driverUserId, idempotencyKey],
    );
  }

  async deleteExpiredBatch(conn, batchSize) {
    const [result] = await conn.query(
      `
        DELETE FROM settlement_receipt_idempotency
        WHERE expires_at < UTC_TIMESTAMP()
        ORDER BY expires_at ASC
        LIMIT ?
      `,
      [batchSize],
    );
    return result.affectedRows ?? 0;
  }
}

module.exports = SettlementReceiptIdempotencyRepository;
