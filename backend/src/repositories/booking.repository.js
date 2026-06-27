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

  buildAdminBookingFilters(filters) {
    const where = ['b.deleted_at IS NULL'];
    const params = [];

    if (filters.status) {
      where.push('b.status = ?');
      params.push(filters.status);
    }

    if (filters.driverId) {
      where.push('b.driver_id = ?');
      params.push(filters.driverId);
    }

    if (filters.serviceDateFrom) {
      where.push('b.scheduled_pickup_at >= ?');
      params.push(filters.serviceDateFrom);
    }

    if (filters.serviceDateTo) {
      where.push('b.scheduled_pickup_at < ?');
      params.push(filters.serviceDateTo);
    }

    if (filters.assignmentState === 'ASSIGNED') {
      where.push(`
        EXISTS (
          SELECT 1 FROM booking_driver_assignments bda
          WHERE bda.booking_id = b.id
            AND bda.is_active = 1
            AND bda.deleted_at IS NULL
        )
      `);
    } else if (filters.assignmentState === 'UNASSIGNED') {
      where.push(`
        NOT EXISTS (
          SELECT 1 FROM booking_driver_assignments bda
          WHERE bda.booking_id = b.id
            AND bda.is_active = 1
            AND bda.deleted_at IS NULL
        )
      `);
    }

    if (filters.search) {
      const term = `%${filters.search}%`;
      where.push(`
        (
          b.booking_number LIKE ?
          OR b.customer_name LIKE ?
          OR b.customer_phone LIKE ?
          OR b.origin_address LIKE ?
          OR b.destination_address LIKE ?
          OR btd.flight_number LIKE ?
        )
      `);
      params.push(term, term, term, term, term, term);
    }

    return { whereSql: where.join(' AND '), params };
  }

  adminQueueSelectSql() {
    return `
      SELECT
        b.id,
        b.booking_number,
        b.status,
        b.scheduled_pickup_at,
        b.origin_address,
        b.destination_address,
        b.customer_name,
        b.customer_phone,
        b.payment_method,
        b.total_amount,
        b.currency,
        b.created_at,
        b.driver_id,
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
        btd.delay_status,
        bda.id AS assignment_id,
        bda.driver_id AS assignment_driver_id,
        bda.status AS assignment_status,
        d.name AS driver_name,
        d.phone AS driver_phone
      FROM bookings b
      INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
      INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
      LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
      LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
      LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
      LEFT JOIN booking_driver_assignments bda ON bda.booking_id = b.id
        AND bda.is_active = 1
        AND bda.deleted_at IS NULL
      LEFT JOIN drivers d ON d.id = bda.driver_id AND d.deleted_at IS NULL
    `;
  }

  async countAdminBookings(filters) {
    const { whereSql, params } = this.buildAdminBookingFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM bookings b
        LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
        WHERE ${whereSql}
      `,
      params,
    );
    return rows[0]?.total ?? 0;
  }

  async findAdminBookings(filters, pagination) {
    const { whereSql, params } = this.buildAdminBookingFilters(filters);
    const limit = pagination.limit;
    const offset = pagination.offset;

    const [rows] = await this.pool.query(
      `
        ${this.adminQueueSelectSql()}
        WHERE ${whereSql}
        ORDER BY
          b.scheduled_pickup_at ASC,
          b.created_at ASC,
          b.booking_number ASC
        LIMIT ? OFFSET ?
      `,
      [...params, limit, offset],
    );
    return rows;
  }

  async findAdminBookingDetail(bookingNumber) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.status,
          b.scheduled_pickup_at,
          b.origin_address,
          b.origin_place_id,
          b.origin_lat,
          b.origin_lng,
          b.destination_address,
          b.destination_place_id,
          b.destination_lat,
          b.destination_lng,
          b.customer_name,
          b.customer_email,
          b.customer_phone,
          b.customer_country_code,
          b.special_requests,
          b.payment_method,
          b.payment_status,
          b.commission_status,
          b.total_amount,
          b.currency,
          b.vehicle_count,
          b.created_at,
          b.updated_at,
          b.metadata,
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
          btd.flight_scheduled_arrival_at,
          btd.flight_estimated_arrival_at,
          btd.delay_status,
          btd.delay_minutes,
          btd.airport_code_custom,
          a.iata_code AS airport_iata
        FROM bookings b
        INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
        INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
        LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
        LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
        LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
        LEFT JOIN airports a ON a.id = btd.airport_id AND a.deleted_at IS NULL
        WHERE b.booking_number = ? AND b.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findChargeItemsByBookingId(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT charge_type, description, quantity, unit_price, amount
        FROM booking_charge_items
        WHERE booking_id = ? AND deleted_at IS NULL
        ORDER BY id ASC
      `,
      [bookingId],
    );
    return rows;
  }

  async findStatusLogsByBookingId(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT from_status, to_status, changed_by_role, reason, memo, created_at
        FROM booking_status_logs
        WHERE booking_id = ?
        ORDER BY created_at ASC
      `,
      [bookingId],
    );
    return rows;
  }

  async findAssignmentsByBookingId(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          bda.id,
          bda.driver_id,
          bda.driver_vehicle_id,
          bda.status,
          bda.is_active,
          bda.assignment_reason,
          bda.assigned_at,
          bda.unassigned_at,
          bda.accepted_at,
          d.name AS driver_name,
          d.phone AS driver_phone
        FROM booking_driver_assignments bda
        LEFT JOIN drivers d ON d.id = bda.driver_id AND d.deleted_at IS NULL
        WHERE bda.booking_id = ? AND bda.deleted_at IS NULL
        ORDER BY bda.assigned_at DESC, bda.id DESC
      `,
      [bookingId],
    );
    return rows;
  }

  async findActiveAssignmentForUpdate(conn, bookingId) {
    const [rows] = await conn.query(
      `
        SELECT
          bda.id,
          bda.driver_id,
          bda.driver_vehicle_id,
          bda.status,
          bda.is_active,
          bda.assignment_reason
        FROM booking_driver_assignments bda
        WHERE bda.booking_id = ?
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async deactivateAssignment(conn, assignmentId, reason) {
    const [result] = await conn.query(
      `
        UPDATE booking_driver_assignments
        SET
          is_active = 0,
          status = 'CANCELLED',
          unassigned_at = CURRENT_TIMESTAMP,
          assignment_reason = COALESCE(?, assignment_reason),
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND is_active = 1
          AND deleted_at IS NULL
      `,
      [reason, assignmentId],
    );
    return result.affectedRows === 1;
  }

  async insertDriverAssignment(conn, row) {
    const [result] = await conn.query(
      `
        INSERT INTO booking_driver_assignments (
          booking_id,
          driver_id,
          driver_vehicle_id,
          status,
          assigned_by_user_id,
          assignment_reason,
          is_active
        ) VALUES (?, ?, ?, 'ASSIGNED', ?, ?, 1)
      `,
      [
        row.bookingId,
        row.driverId,
        row.driverVehicleId ?? null,
        row.assignedByUserId,
        row.assignmentReason ?? null,
      ],
    );
    return result.insertId;
  }

  settlementSelectSql() {
    return `
      SELECT
        b.id,
        b.booking_number,
        b.status,
        b.completed_at,
        b.total_amount,
        b.currency,
        b.commission_status,
        b.commission_amount,
        b.commission_due_at,
        b.commission_paid_at,
        b.commission_receipt_file_id,
        b.metadata,
        b.driver_id,
        d.name AS driver_name,
        d.phone AS driver_phone,
        f.mime_type AS receipt_mime_type,
        f.file_size AS receipt_file_size,
        f.original_filename AS receipt_original_filename,
        f.created_at AS receipt_uploaded_at
      FROM bookings b
      LEFT JOIN drivers d ON d.id = b.driver_id AND d.deleted_at IS NULL
      LEFT JOIN files f ON f.id = b.commission_receipt_file_id AND f.deleted_at IS NULL
    `;
  }

  async findSettlementByBookingNumberForUpdate(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        ${this.settlementSelectSql()}
        WHERE b.booking_number = ? AND b.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findSettlementByBookingNumber(bookingNumber) {
    const [rows] = await this.pool.query(
      `
        ${this.settlementSelectSql()}
        WHERE b.booking_number = ? AND b.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async updateCommissionFields(conn, bookingId, fields) {
    const sets = [];
    const params = [];
    if (fields.commissionStatus !== undefined) {
      sets.push('commission_status = ?');
      params.push(fields.commissionStatus);
    }
    if (fields.commissionAmount !== undefined) {
      sets.push('commission_amount = ?');
      params.push(fields.commissionAmount);
    }
    if (fields.commissionDueAt !== undefined) {
      sets.push('commission_due_at = ?');
      params.push(fields.commissionDueAt);
    }
    if (fields.commissionPaidAt !== undefined) {
      sets.push('commission_paid_at = ?');
      params.push(fields.commissionPaidAt);
    }
    if (fields.commissionReceiptFileId !== undefined) {
      sets.push('commission_receipt_file_id = ?');
      params.push(fields.commissionReceiptFileId);
    }
    if (fields.metadata !== undefined) {
      sets.push('metadata = ?');
      params.push(fields.metadata ? JSON.stringify(fields.metadata) : null);
    }
    if (fields.updatedBy !== undefined) {
      sets.push('updated_by = ?');
      params.push(fields.updatedBy);
    }
    if (!sets.length) return;
    params.push(bookingId);
    await conn.query(
      `
        UPDATE bookings
        SET ${sets.join(', ')}, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      params,
    );
  }

  async driverOwnsSettlementBooking(driverId, bookingNumber) {
    const [rows] = await this.pool.query(
      `
        SELECT 1
        FROM bookings b
        INNER JOIN booking_driver_assignments bda
          ON bda.booking_id = b.id AND bda.deleted_at IS NULL
        WHERE b.booking_number = ?
          AND b.deleted_at IS NULL
          AND b.status = 'COMPLETED'
          AND bda.driver_id = ?
        LIMIT 1
      `,
      [bookingNumber, driverId],
    );
    return rows.length > 0;
  }

  async findDriverSettlements(driverId) {
    const [rows] = await this.pool.query(
      `
        ${this.settlementSelectSql()}
        INNER JOIN booking_driver_assignments bda
          ON bda.booking_id = b.id AND bda.deleted_at IS NULL
        WHERE bda.driver_id = ?
          AND b.status = 'COMPLETED'
          AND b.deleted_at IS NULL
          AND b.commission_status NOT IN ('NOT_DUE_YET', 'WAIVED')
        GROUP BY b.id
        ORDER BY b.completed_at DESC, b.booking_number DESC
      `,
      [driverId],
    );
    return rows;
  }

  buildAdminSettlementFilters(filters) {
    const where = [
      'b.deleted_at IS NULL',
      'b.status = \'COMPLETED\'',
      'b.commission_status NOT IN (\'NOT_DUE_YET\', \'WAIVED\')',
    ];
    const params = [];

    if (filters.status) {
      if (filters.status === 'OVERDUE') {
        where.push('(b.commission_status = \'OVERDUE\' OR (b.commission_status = \'DUE\' AND b.commission_due_at IS NOT NULL AND b.commission_due_at < NOW()))');
      } else if (filters.status === 'PENDING') {
        where.push('b.commission_status = \'DUE\' AND (b.commission_due_at IS NULL OR b.commission_due_at >= NOW()) AND b.commission_receipt_file_id IS NULL');
      } else if (filters.status === 'RECEIPT_SUBMITTED') {
        where.push('b.commission_receipt_file_id IS NOT NULL AND b.commission_status IN (\'DUE\', \'OVERDUE\')');
      } else if (filters.status === 'APPROVED') {
        where.push('b.commission_status = \'PAID\'');
      } else if (filters.status === 'REJECTED') {
        where.push('JSON_UNQUOTE(JSON_EXTRACT(b.metadata, \'$.commissionRejectionReason\')) IS NOT NULL AND b.commission_receipt_file_id IS NULL');
      }
    }

    if (filters.driverId) {
      where.push('b.driver_id = ?');
      params.push(filters.driverId);
    }

    if (filters.bookingNumber) {
      where.push('b.booking_number = ?');
      params.push(filters.bookingNumber);
    }

    if (filters.completedDateFrom) {
      where.push('b.completed_at >= ?');
      params.push(filters.completedDateFrom);
    }

    if (filters.completedDateTo) {
      where.push('b.completed_at < ?');
      params.push(filters.completedDateTo);
    }

    if (filters.overdueOnly) {
      where.push('(b.commission_status = \'OVERDUE\' OR (b.commission_status = \'DUE\' AND b.commission_due_at IS NOT NULL AND b.commission_due_at < NOW()))');
    }

    return { whereSql: where.join(' AND '), params };
  }

  async countAdminSettlements(filters) {
    const { whereSql, params } = this.buildAdminSettlementFilters(filters);
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM bookings b
        WHERE ${whereSql}
      `,
      params,
    );
    return rows[0]?.total ?? 0;
  }

  async findAdminSettlements(filters, pagination) {
    const { whereSql, params } = this.buildAdminSettlementFilters(filters);
    const limit = pagination.limit;
    const offset = pagination.offset;
    const [rows] = await this.pool.query(
      `
        ${this.settlementSelectSql()}
        WHERE ${whereSql}
        ORDER BY b.completed_at DESC, b.booking_number DESC
        LIMIT ? OFFSET ?
      `,
      [...params, limit, offset],
    );
    return rows;
  }

  async countBlockingSettlementsForDriver(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM bookings b
        WHERE b.driver_id = ?
          AND b.deleted_at IS NULL
          AND b.status = 'COMPLETED'
          AND b.commission_status IN ('DUE', 'OVERDUE')
          AND (
            b.commission_status = 'OVERDUE'
            OR (
              b.commission_due_at IS NOT NULL
              AND b.commission_due_at < NOW()
              AND b.commission_receipt_file_id IS NULL
            )
          )
      `,
      [driverId],
    );
    return Number(rows[0]?.total ?? 0);
  }

  buildAdminMissingObligationScope(filters) {
    const where = [
      'b.deleted_at IS NULL',
      'b.status = \'COMPLETED\'',
      `(
        b.commission_status = 'NOT_DUE_YET'
        OR b.commission_status = 'PENDING_AFTER_COMPLETION'
        OR b.commission_amount IS NULL
      )`,
    ];
    const params = [];

    if (filters.driverId) {
      where.push('b.driver_id = ?');
      params.push(filters.driverId);
    }

    if (filters.bookingNumber) {
      where.push('b.booking_number = ?');
      params.push(filters.bookingNumber);
    }

    if (filters.completedDateFrom) {
      where.push('b.completed_at >= ?');
      params.push(filters.completedDateFrom);
    }

    if (filters.completedDateTo) {
      where.push('b.completed_at < ?');
      params.push(filters.completedDateTo);
    }

    return { whereSql: where.join(' AND '), params };
  }

  async findCompletedBookingIdsMissingObligationForAdmin(filters, limit = 100) {
    const { whereSql, params } = this.buildAdminMissingObligationScope(filters);
    const [rows] = await this.pool.query(
      `
        SELECT b.id
        FROM bookings b
        WHERE ${whereSql}
        ORDER BY b.completed_at DESC, b.id DESC
        LIMIT ?
      `,
      [...params, limit],
    );
    return rows.map((row) => row.id);
  }

  async findCompletedBookingIdsMissingObligation(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT b.id
        FROM bookings b
        INNER JOIN booking_driver_assignments bda ON bda.booking_id = b.id
          AND bda.driver_id = ?
          AND bda.deleted_at IS NULL
        WHERE b.deleted_at IS NULL
          AND b.status = 'COMPLETED'
          AND (
            b.commission_status = 'NOT_DUE_YET'
            OR b.commission_status = 'PENDING_AFTER_COMPLETION'
            OR b.commission_amount IS NULL
          )
      `,
      [driverId],
    );
    return rows.map((row) => row.id);
  }

  async findUnpaidSettlementsForDriver(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id,
          b.commission_status,
          b.commission_due_at,
          b.commission_receipt_file_id,
          b.metadata
        FROM bookings b
        WHERE b.driver_id = ?
          AND b.deleted_at IS NULL
          AND b.status = 'COMPLETED'
          AND b.commission_status NOT IN ('PAID', 'WAIVED', 'NOT_DUE_YET')
      `,
      [driverId],
    );
    return rows;
  }
}

module.exports = BookingRepository;
