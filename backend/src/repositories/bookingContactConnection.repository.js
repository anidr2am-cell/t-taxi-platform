const CONTACT_STATUS = require('../constants/contactStatus');
const CONTACT_CHANNEL = require('../constants/contactChannel');

const ACTIVE_CONNECTION_STATUSES = ['PENDING', 'CONFIRM_REQUESTED', 'VERIFIED'];

class BookingContactConnectionRepository {
  constructor(pool) {
    this.pool = pool;
  }

  async insertConnection(conn, row) {
    const executor = conn ?? this.pool;
    const [result] = await executor.query(
      `
        INSERT INTO booking_contact_connections (
          booking_id, channel, status,
          provider_user_id, external_handle,
          customer_confirmed_at, admin_verified_at, admin_verified_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        row.bookingId,
        row.channel,
        row.status ?? CONTACT_STATUS.PENDING,
        row.providerUserId ?? null,
        row.externalHandle ?? null,
        row.customerConfirmedAt ?? null,
        row.adminVerifiedAt ?? null,
        row.adminVerifiedBy ?? null,
      ],
    );
    return result.insertId;
  }

  async cancelActiveConnections(conn, bookingId) {
    const executor = conn ?? this.pool;
    await executor.query(
      `
        UPDATE booking_contact_connections
        SET status = 'CANCELLED', updated_at = UTC_TIMESTAMP()
        WHERE booking_id = ?
          AND status IN ('PENDING', 'CONFIRM_REQUESTED')
      `,
      [bookingId],
    );
  }

  async findActiveByBookingId(conn, bookingId) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT *
        FROM booking_contact_connections
        WHERE booking_id = ?
          AND status IN (?, ?, ?)
        ORDER BY updated_at DESC, id DESC
        LIMIT 1
      `,
      [bookingId, ...ACTIVE_CONNECTION_STATUSES],
    );
    return rows[0] ?? null;
  }

  async findById(conn, connectionId) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      'SELECT * FROM booking_contact_connections WHERE id = ? LIMIT 1',
      [connectionId],
    );
    return rows[0] ?? null;
  }

  async updateConnectionStatus(conn, connectionId, patch) {
    const executor = conn ?? this.pool;
    await executor.query(
      `
        UPDATE booking_contact_connections
        SET status = ?,
            customer_confirmed_at = COALESCE(?, customer_confirmed_at),
            admin_verified_at = COALESCE(?, admin_verified_at),
            admin_verified_by = COALESCE(?, admin_verified_by),
            updated_at = UTC_TIMESTAMP()
        WHERE id = ?
      `,
      [
        patch.status,
        patch.customerConfirmedAt ?? null,
        patch.adminVerifiedAt ?? null,
        patch.adminVerifiedBy ?? null,
        connectionId,
      ],
    );
  }

  async updateBookingContactSnapshot(conn, bookingId, patch) {
    const executor = conn ?? this.pool;
    await executor.query(
      `
        UPDATE bookings
        SET contact_status = ?,
            contact_channel = COALESCE(?, contact_channel),
            contact_requested_at = COALESCE(?, contact_requested_at),
            contact_verified_at = COALESCE(?, contact_verified_at),
            updated_at = UTC_TIMESTAMP()
        WHERE id = ?
      `,
      [
        patch.contactStatus,
        patch.contactChannel ?? null,
        patch.contactRequestedAt ?? null,
        patch.contactVerifiedAt ?? null,
        bookingId,
      ],
    );
  }

  static isAllowedChannel(channel) {
    return Object.values(CONTACT_CHANNEL).includes(channel);
  }
}

module.exports = BookingContactConnectionRepository;
