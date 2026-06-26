const database = require('../config/database');
const { toDatabaseChargeType } = require('../utils/chargeTypeDb.util');

class BookingRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async insertBooking(conn, row) {
    const [result] = await conn.query(
      `
        INSERT INTO bookings (
          booking_number, status, service_type_id,
          origin_address, origin_place_id, origin_lat, origin_lng,
          destination_address, destination_place_id, destination_lat, destination_lng,
          scheduled_pickup_at, vehicle_type_id, recommended_vehicle_type_id, vehicle_count,
          route_id, total_amount, currency, payment_status, payment_method, commission_status,
          customer_user_id, customer_name, customer_email, customer_phone, customer_country_code,
          special_requests, metadata, boarding_qr_token_hash, boarding_qr_expires_at,
          created_by, updated_by
        ) VALUES (
          ?, ?, ?,
          ?, ?, ?, ?,
          ?, ?, ?, ?,
          ?, ?, ?, ?,
          ?, 0.00, ?, ?, ?, ?,
          ?, ?, ?, ?, ?,
          ?, ?, ?, ?,
          ?, ?
        )
      `,
      [
        row.bookingNumber,
        row.status,
        row.serviceTypeId,
        row.originAddress,
        row.originPlaceId,
        row.originLat,
        row.originLng,
        row.destinationAddress,
        row.destinationPlaceId,
        row.destinationLat,
        row.destinationLng,
        row.scheduledPickupAt,
        row.vehicleTypeId,
        row.recommendedVehicleTypeId,
        row.vehicleCount,
        row.routeId,
        row.currency,
        row.paymentStatus,
        row.paymentMethod,
        row.commissionStatus,
        row.customerUserId,
        row.customerName,
        row.customerEmail,
        row.customerPhone,
        row.customerCountryCode,
        row.specialRequests,
        row.metadata ? JSON.stringify(row.metadata) : null,
        row.boardingQrTokenHash,
        row.boardingQrExpiresAt,
        row.createdBy,
        row.updatedBy,
      ],
    );
    return result.insertId;
  }

  async insertPassengers(conn, bookingId, passengers) {
    await conn.query(
      `
        INSERT INTO booking_passengers (booking_id, adults, children, infants)
        VALUES (?, ?, ?, ?)
      `,
      [bookingId, passengers.adults, passengers.children, passengers.infants],
    );
  }

  async insertLuggage(conn, bookingId, luggage) {
    await conn.query(
      `
        INSERT INTO booking_luggage (
          booking_id, carriers_20_inch, carriers_24_inch_plus, golf_bags, special_items
        ) VALUES (?, ?, ?, ?, ?)
      `,
      [
        bookingId,
        luggage.carriers20Inch,
        luggage.carriers24InchPlus,
        luggage.golfBags,
        luggage.specialItems,
      ],
    );
  }

  async insertTransferDetails(conn, bookingId, transfer) {
    await conn.query(
      `
        INSERT INTO booking_transfer_details (
          booking_id, airport_id, airport_code_custom, flight_number,
          golf_course_id, golf_region, driver_included
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        bookingId,
        transfer.airportId,
        transfer.airportCodeCustom,
        transfer.flightNumber,
        transfer.golfCourseId,
        transfer.golfRegion,
        transfer.driverIncluded ? 1 : 0,
      ],
    );
  }

  async insertChargeItem(conn, bookingId, item, createdBy) {
    await conn.query(
      `
        INSERT INTO booking_charge_items (
          booking_id, charge_type, description, quantity, unit_price, amount,
          reference_type, reference_id, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        bookingId,
        item.chargeType ? toDatabaseChargeType(item.chargeType) : item.chargeType,
        item.description,
        item.quantity,
        item.unitPrice,
        item.amount,
        item.referenceType,
        item.referenceId,
        createdBy,
      ],
    );
  }

  async insertStatusLog(conn, bookingId, log) {
    await conn.query(
      `
        INSERT INTO booking_status_logs (
          booking_id, from_status, to_status, changed_by_user_id, changed_by_role, reason, memo
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        bookingId,
        log.fromStatus,
        log.toStatus,
        log.changedByUserId,
        log.changedByRole,
        log.reason,
        log.memo ?? null,
      ],
    );
  }

  async insertActivityLog(conn, bookingId, activity) {
    await conn.query(
      `
        INSERT INTO booking_activity_logs (
          booking_id, activity_type, actor_user_id, actor_role, description, payload
        ) VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        bookingId,
        activity.activityType,
        activity.actorUserId,
        activity.actorRole,
        activity.description,
        activity.payload ? JSON.stringify(activity.payload) : null,
      ],
    );
  }

  async insertGuestToken(conn, bookingId, tokenHash, expiresAt) {
    await conn.query(
      `
        INSERT INTO guest_access_tokens (booking_id, token_hash, expires_at)
        VALUES (?, ?, ?)
      `,
      [bookingId, tokenHash, expiresAt],
    );
  }

  async findById(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT id, booking_number, status, total_amount, currency, payment_status, payment_method
        FROM bookings
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findByBookingNumberForUpdate(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id, b.booking_number, b.status, b.total_amount, b.currency,
          b.payment_status, b.payment_method, b.customer_user_id, b.driver_id,
          b.dropoff_qr_token_hash, b.dropoff_qr_expires_at, b.dropoff_qr_used_at,
          d.user_id AS driver_user_id
        FROM bookings b
        LEFT JOIN drivers d ON d.id = b.driver_id AND d.deleted_at IS NULL
        WHERE b.booking_number = ? AND b.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findActiveGuestTokenForBooking(conn, bookingId, tokenHash) {
    const [rows] = await conn.query(
      `
        SELECT id
        FROM guest_access_tokens
        WHERE
          booking_id = ?
          AND token_hash = ?
          AND revoked_at IS NULL
          AND expires_at > CURRENT_TIMESTAMP
        LIMIT 1
      `,
      [bookingId, tokenHash],
    );
    return rows[0] || null;
  }

  driverJobSelectSql() {
    return `
      SELECT
        b.id,
        b.booking_number,
        b.status,
        b.scheduled_pickup_at,
        DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d') AS pickup_date,
        DATE_FORMAT(b.scheduled_pickup_at, '%H:%i') AS pickup_time,
        b.origin_address,
        b.destination_address,
        b.customer_name,
        b.customer_phone,
        b.special_requests,
        b.payment_method,
        b.boarding_qr_token_hash,
        b.boarding_qr_expires_at,
        b.boarding_qr_used_at,
        b.dropoff_qr_token_hash,
        b.dropoff_qr_expires_at,
        b.dropoff_qr_used_at,
        st.code AS service_type_code,
        st.name AS service_type_name,
        vt.code AS vehicle_type_code,
        vt.name AS vehicle_type_name,
        bp.adults,
        bp.children,
        bp.infants,
        bl.carriers_20_inch,
        bl.carriers_24_inch_plus,
        bl.golf_bags,
        bl.special_items,
        btd.flight_number,
        btd.flight_estimated_arrival_at,
        DATE_FORMAT(btd.flight_estimated_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_estimated_arrival_at_text,
        btd.delay_status,
        btd.delay_minutes
      FROM booking_driver_assignments bda
      INNER JOIN drivers d ON d.id = bda.driver_id AND d.deleted_at IS NULL
      INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
      INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
      INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
      LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
      LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
      LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
      WHERE
        d.user_id = ?
        AND d.is_active = 1
        AND bda.is_active = 1
        AND bda.deleted_at IS NULL
        AND bda.status IN ('ASSIGNED', 'ACCEPTED')
    `;
  }

  async findActiveDriverBookingsForDate(driverUserId, dateRange) {
    const [rows] = await this.pool.query(
      `
        ${this.driverJobSelectSql()}
        AND b.status <> 'CANCELLED'
        AND b.scheduled_pickup_at >= ?
        AND b.scheduled_pickup_at < ?
        ORDER BY b.scheduled_pickup_at ASC, b.booking_number ASC
      `,
      [driverUserId, dateRange.start, dateRange.end],
    );
    return rows;
  }

  async findActiveDriverBookingByNumber(driverUserId, bookingNumber) {
    const [rows] = await this.pool.query(
      `
        ${this.driverJobSelectSql()}
        AND b.booking_number = ?
        LIMIT 1
      `,
      [driverUserId, bookingNumber],
    );
    return rows[0] || null;
  }

  async findActiveDriverBookingByNumberForUpdate(conn, driverUserId, bookingNumber) {
    const [rows] = await conn.query(
      `
        ${this.driverJobSelectSql()}
        AND b.booking_number = ?
        LIMIT 1
        FOR UPDATE
      `,
      [driverUserId, bookingNumber],
    );
    return rows[0] || null;
  }

  async findQrTokenBooking(conn, tokenHash) {
    const [rows] = await conn.query(
      `
        SELECT
          id,
          booking_number,
          CASE
            WHEN boarding_qr_token_hash = ? THEN 'BOARDING'
            WHEN dropoff_qr_token_hash = ? THEN 'DROPOFF'
            ELSE NULL
          END AS token_type
        FROM bookings
        WHERE
          deleted_at IS NULL
          AND (boarding_qr_token_hash = ? OR dropoff_qr_token_hash = ?)
        LIMIT 1
      `,
      [tokenHash, tokenHash, tokenHash, tokenHash],
    );
    return rows[0] || null;
  }

  async markBoardingQrUsed(conn, bookingId) {
    const [result] = await conn.query(
      `
        UPDATE bookings
        SET boarding_qr_used_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL AND boarding_qr_used_at IS NULL
      `,
      [bookingId],
    );
    return result.affectedRows === 1;
  }

  async markDropoffQrUsed(conn, bookingId) {
    const [result] = await conn.query(
      `
        UPDATE bookings
        SET dropoff_qr_used_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL AND dropoff_qr_used_at IS NULL
      `,
      [bookingId],
    );
    return result.affectedRows === 1;
  }

  async setDropoffQr(conn, bookingId, tokenHash, expiresAt) {
    await conn.query(
      `
        UPDATE bookings
        SET
          dropoff_qr_token_hash = ?,
          dropoff_qr_expires_at = ?,
          dropoff_qr_used_at = NULL
        WHERE id = ? AND deleted_at IS NULL
      `,
      [tokenHash, expiresAt, bookingId],
    );
  }

  async updateStatus(conn, bookingId, status, actorUserId, statusFields = {}) {
    await conn.query(
      `
        UPDATE bookings
        SET
          status = ?,
          updated_by = ?,
          cancelled_at = CASE WHEN ? = 'CANCELLED' THEN CURRENT_TIMESTAMP ELSE cancelled_at END,
          cancellation_reason = CASE WHEN ? = 'CANCELLED' THEN ? ELSE cancellation_reason END,
          completed_at = CASE WHEN ? = 'COMPLETED' THEN CURRENT_TIMESTAMP ELSE completed_at END
        WHERE id = ? AND deleted_at IS NULL
      `,
      [
        status,
        actorUserId,
        status,
        status,
        statusFields.cancellationReason ?? null,
        status,
        bookingId,
      ],
    );
  }

  async findAirportByIata(conn, iataCode) {
    const [rows] = await conn.query(
      `
        SELECT id, iata_code, name
        FROM airports
        WHERE iata_code = ? AND deleted_at IS NULL AND is_active = 1
        LIMIT 1
      `,
      [iataCode],
    );
    return rows[0] || null;
  }
}

module.exports = BookingRepository;
