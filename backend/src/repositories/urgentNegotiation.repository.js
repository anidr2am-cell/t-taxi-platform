class UrgentNegotiationRepository {
  constructor(pool) {
    this.pool = pool;
  }

  async findBookingForUrgentLock(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.is_urgent_request,
          b.urgent_negotiation_id,
          b.status,
          b.scheduled_pickup_at,
          b.customer_user_id,
          b.vehicle_type_id
        FROM bookings b
        WHERE b.booking_number = ?
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        LIMIT 1
        FOR UPDATE
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findBookingForCustomer(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.is_urgent_request,
          b.urgent_negotiation_id,
          b.status,
          b.scheduled_pickup_at,
          b.customer_user_id,
          b.vehicle_type_id
        FROM bookings b
        WHERE b.booking_number = ?
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findBookingForUrgentLockById(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.is_urgent_request,
          b.urgent_negotiation_id,
          b.status,
          b.scheduled_pickup_at,
          b.customer_user_id,
          b.vehicle_type_id
        FROM bookings b
        WHERE b.id = ?
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findBroadcastingNegotiationForUpdate(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          status,
          attempt_count,
          locked_driver_id
        FROM booking_urgent_negotiations
        WHERE booking_id = ?
          AND status = 'BROADCASTING'
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async lockNegotiationIfBroadcasting(conn, { negotiationId, driverId }) {
    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiations
        SET
          locked_driver_id = ?,
          status = 'LOCKED',
          locked_at = CURRENT_TIMESTAMP(3),
          lock_expires_at = CURRENT_TIMESTAMP(3) + INTERVAL 3 MINUTE,
          updated_at = CURRENT_TIMESTAMP(3)
        WHERE id = ?
          AND status = 'BROADCASTING'
          AND locked_driver_id IS NULL
      `,
      [driverId, negotiationId],
    );
    return result.affectedRows;
  }

  async findNegotiationById(conn, negotiationId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          status,
          attempt_count,
          locked_driver_id,
          locked_at,
          lock_expires_at,
          customer_decision_expires_at
        FROM booking_urgent_negotiations
        WHERE id = ?
        LIMIT 1
      `,
      [negotiationId],
    );
    return rows[0] || null;
  }

  async insertAttempt(conn, { negotiationId, attemptNumber, driverId }) {
    const [result] = await conn.query(
      `
        INSERT INTO booking_urgent_negotiation_attempts (
          negotiation_id,
          attempt_number,
          driver_id,
          outcome
        ) VALUES (?, ?, ?, 'IN_PROGRESS')
      `,
      [negotiationId, attemptNumber, driverId],
    );
    return result.insertId;
  }

  async findNegotiationByBookingIdForUpdate(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          status,
          attempt_count,
          locked_driver_id,
          locked_at,
          lock_expires_at,
          min_required_eta_minutes,
          customer_decision_expires_at
        FROM booking_urgent_negotiations
        WHERE booking_id = ?
        ORDER BY id DESC
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findNegotiationByBookingId(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          status,
          attempt_count,
          locked_driver_id,
          locked_at,
          lock_expires_at,
          min_required_eta_minutes,
          customer_decision_expires_at,
          closed_reason
        FROM booking_urgent_negotiations
        WHERE booking_id = ?
        ORDER BY id DESC
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async markNegotiationAwaitingCustomer(conn, negotiationId) {
    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiations
        SET
          status = 'AWAITING_CUSTOMER',
          customer_decision_expires_at = CURRENT_TIMESTAMP(3) + INTERVAL 2 MINUTE,
          updated_at = CURRENT_TIMESTAMP(3)
        WHERE id = ?
          AND status = 'LOCKED'
      `,
      [negotiationId],
    );
    if (result.affectedRows !== 1) return null;
    return this.findNegotiationById(conn, negotiationId);
  }

  async updateLatestAttemptEta(conn, { negotiationId, etaMinutes }) {
    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiation_attempts
        SET
          proposed_eta_minutes = ?,
          eta_submitted_at = CURRENT_TIMESTAMP(3)
        WHERE negotiation_id = ?
          AND attempt_number = (
            SELECT attempt_number
            FROM (
              SELECT MAX(attempt_number) AS attempt_number
              FROM booking_urgent_negotiation_attempts
              WHERE negotiation_id = ?
            ) latest
          )
      `,
      [etaMinutes, negotiationId, negotiationId],
    );
    return result.affectedRows;
  }

  async findLatestAttempt(conn, negotiationId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          attempt_number,
          driver_id,
          proposed_eta_minutes,
          eta_submitted_at,
          outcome
        FROM booking_urgent_negotiation_attempts
        WHERE negotiation_id = ?
        ORDER BY attempt_number DESC
        LIMIT 1
      `,
      [negotiationId],
    );
    return rows[0] || null;
  }

  async updateLatestAttemptOutcome(conn, { negotiationId, outcome }) {
    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiation_attempts
        SET
          outcome = ?,
          outcome_at = CURRENT_TIMESTAMP(3)
        WHERE negotiation_id = ?
          AND attempt_number = (
            SELECT attempt_number
            FROM (
              SELECT MAX(attempt_number) AS attempt_number
              FROM booking_urgent_negotiation_attempts
              WHERE negotiation_id = ?
            ) latest
          )
      `,
      [outcome, negotiationId, negotiationId],
    );
    return result.affectedRows;
  }

  async confirmNegotiation(conn, negotiationId) {
    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiations
        SET
          status = 'CONFIRMED',
          closed_at = CURRENT_TIMESTAMP(3),
          closed_reason = 'CUSTOMER_ACCEPTED',
          customer_decision_expires_at = NULL,
          updated_at = CURRENT_TIMESTAMP(3)
        WHERE id = ?
          AND status = 'AWAITING_CUSTOMER'
      `,
      [negotiationId],
    );
    if (result.affectedRows !== 1) return null;
    return this.findNegotiationById(conn, negotiationId);
  }

  async rejectAndRebroadcast(conn, { negotiationId, minRequiredEtaMinutes }) {
    return this.rebroadcastAfterAttemptFailure(conn, {
      negotiationId,
      fromStatus: 'AWAITING_CUSTOMER',
      minRequiredEtaMinutes,
    });
  }

  async cancelNegotiationExhausted(conn, { negotiationId, minRequiredEtaMinutes }) {
    return this.cancelAfterAttemptFailure(conn, {
      negotiationId,
      fromStatus: 'AWAITING_CUSTOMER',
      minRequiredEtaMinutes,
    });
  }

  async findActiveNegotiationForBookingForUpdate(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          status,
          attempt_count,
          locked_driver_id,
          min_required_eta_minutes
        FROM booking_urgent_negotiations
        WHERE booking_id = ?
          AND status NOT IN ('CONFIRMED', 'CANCELLED')
        ORDER BY id DESC
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async insertNegotiation(conn, { bookingId }) {
    const [result] = await conn.query(
      `
        INSERT INTO booking_urgent_negotiations (
          booking_id,
          status,
          attempt_count,
          min_required_eta_minutes
        ) VALUES (?, 'BROADCASTING', 0, NULL)
      `,
      [bookingId],
    );
    return result.insertId;
  }

  async listExpiredLockedNegotiations(limit = 20) {
    const [rows] = await this.pool.query(
      `
        SELECT
          n.id,
          n.booking_id,
          n.status,
          n.attempt_count,
          n.locked_driver_id,
          n.lock_expires_at,
          n.min_required_eta_minutes,
          b.booking_number,
          b.status AS booking_status
        FROM booking_urgent_negotiations n
        INNER JOIN bookings b ON b.id = n.booking_id
        WHERE n.status = 'LOCKED'
          AND n.lock_expires_at IS NOT NULL
          AND n.lock_expires_at <= CURRENT_TIMESTAMP(3)
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        ORDER BY n.lock_expires_at ASC
        LIMIT ?
      `,
      [limit],
    );
    return rows;
  }

  async listExpiredAwaitingCustomerNegotiations(limit = 20) {
    const [rows] = await this.pool.query(
      `
        SELECT
          n.id,
          n.booking_id,
          n.status,
          n.attempt_count,
          n.locked_driver_id,
          n.customer_decision_expires_at,
          n.min_required_eta_minutes,
          b.booking_number,
          b.status AS booking_status
        FROM booking_urgent_negotiations n
        INNER JOIN bookings b ON b.id = n.booking_id
        WHERE n.status = 'AWAITING_CUSTOMER'
          AND n.customer_decision_expires_at IS NOT NULL
          AND n.customer_decision_expires_at <= CURRENT_TIMESTAMP(3)
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        ORDER BY n.customer_decision_expires_at ASC
        LIMIT ?
      `,
      [limit],
    );
    return rows;
  }

  async findNegotiationByIdForUpdate(conn, negotiationId) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_id,
          status,
          attempt_count,
          locked_driver_id,
          locked_at,
          lock_expires_at,
          min_required_eta_minutes,
          customer_decision_expires_at,
          closed_at,
          closed_reason
        FROM booking_urgent_negotiations
        WHERE id = ?
        LIMIT 1
        FOR UPDATE
      `,
      [negotiationId],
    );
    return rows[0] || null;
  }

  async rebroadcastAfterAttemptFailure(
    conn,
    { negotiationId, fromStatus, minRequiredEtaMinutes = undefined },
  ) {
    const params = [negotiationId, fromStatus];
    let minSetClause = 'min_required_eta_minutes = min_required_eta_minutes';
    if (minRequiredEtaMinutes != null) {
      minSetClause = 'min_required_eta_minutes = ?';
      params.unshift(minRequiredEtaMinutes);
    }

    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiations
        SET
          status = 'BROADCASTING',
          attempt_count = attempt_count + 1,
          ${minSetClause},
          locked_driver_id = NULL,
          locked_at = NULL,
          lock_expires_at = NULL,
          customer_decision_expires_at = NULL,
          updated_at = CURRENT_TIMESTAMP(3)
        WHERE id = ?
          AND status = ?
      `,
      params,
    );
    if (result.affectedRows !== 1) return null;
    return this.findNegotiationById(conn, negotiationId);
  }

  async cancelAfterAttemptFailure(
    conn,
    { negotiationId, fromStatus, minRequiredEtaMinutes = undefined },
  ) {
    const params = [negotiationId, fromStatus];
    let minSetClause = 'min_required_eta_minutes = min_required_eta_minutes';
    if (minRequiredEtaMinutes != null) {
      minSetClause = 'min_required_eta_minutes = ?';
      params.unshift(minRequiredEtaMinutes);
    }

    const [result] = await conn.query(
      `
        UPDATE booking_urgent_negotiations
        SET
          status = 'CANCELLED',
          attempt_count = attempt_count + 1,
          ${minSetClause},
          locked_driver_id = NULL,
          locked_at = NULL,
          lock_expires_at = NULL,
          customer_decision_expires_at = NULL,
          closed_at = CURRENT_TIMESTAMP(3),
          closed_reason = 'URGENT_NEGOTIATION_EXHAUSTED',
          updated_at = CURRENT_TIMESTAMP(3)
        WHERE id = ?
          AND status = ?
      `,
      params,
    );
    if (result.affectedRows !== 1) return null;
    return this.findNegotiationById(conn, negotiationId);
  }
}

module.exports = UrgentNegotiationRepository;
