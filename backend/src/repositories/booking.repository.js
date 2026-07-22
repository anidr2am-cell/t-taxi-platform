const database = require('../config/database');

const SETTLEMENT_ELIGIBLE_BOOKING_STATUSES_SQL = "'SETTLEMENT_PENDING', 'COMPLETED'";

class BookingRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  activeAssignmentExistsSql() {
    return `
      EXISTS (
        SELECT 1 FROM booking_driver_assignments active_bda
        WHERE active_bda.booking_id = b.id
          AND active_bda.is_active = 1
          AND active_bda.deleted_at IS NULL
      )
    `;
  }

  activeAssignmentMissingSql() {
    return `
      NOT EXISTS (
        SELECT 1 FROM booking_driver_assignments active_bda
        WHERE active_bda.booking_id = b.id
          AND active_bda.is_active = 1
          AND active_bda.deleted_at IS NULL
      )
    `;
  }

  unassignedBookingSql() {
    return `
      ${this.activeAssignmentMissingSql()}
      AND b.status IN ('PENDING', 'OPEN', 'CONFIRMED')
    `;
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
          ?, ?, ?, ?, ?, ?,
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
        row.totalAmount ?? 0,
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
          airline_code, flight_date,
          golf_course_id, golf_region, driver_included
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        bookingId,
        transfer.airportId,
        transfer.airportCodeCustom,
        transfer.flightNumber,
        transfer.airlineCode ?? null,
        transfer.flightDate ?? null,
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
        item.chargeType,
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
        SELECT
          b.id,
          b.booking_number,
          b.status,
          b.total_amount,
          b.currency,
          b.payment_status,
          b.payment_method,
          b.customer_user_id,
          COALESCE(b.driver_id, bda.driver_id) AS driver_id,
          d.user_id AS driver_user_id
        FROM bookings b
        LEFT JOIN booking_driver_assignments bda
          ON bda.booking_id = b.id
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
        LEFT JOIN drivers d
          ON d.id = COALESCE(b.driver_id, bda.driver_id)
          AND d.deleted_at IS NULL
        WHERE b.id = ? AND b.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] || null;
  }

  async findByBookingNumber(bookingNumber) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.status,
          b.customer_user_id,
          COALESCE(b.driver_id, bda.driver_id) AS driver_id
        FROM bookings b
        LEFT JOIN booking_driver_assignments bda ON bda.id = (
          SELECT bda2.id
          FROM booking_driver_assignments bda2
          WHERE bda2.booking_id = b.id
            AND bda2.deleted_at IS NULL
            AND (
              bda2.is_active = 1
              OR b.status IN ('SETTLEMENT_PENDING', 'COMPLETED')
            )
          ORDER BY bda2.is_active DESC, bda2.updated_at DESC, bda2.id DESC
          LIMIT 1
        )
        WHERE b.booking_number = ? AND b.deleted_at IS NULL AND b.is_archived = 0
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findGuestLookupBookingByNumber(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.status,
          COALESCE(b.driver_id, bda.driver_id) AS driver_id,
          DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d %H:%i:%s') AS scheduled_pickup_at_text,
          b.origin_address,
          b.destination_address,
          b.customer_phone,
          b.customer_country_code,
          b.payment_method,
          b.payment_status,
          b.total_amount,
          b.currency,
          b.vehicle_count,
          b.route_id,
          b.boarding_qr_token_hash,
          b.boarding_qr_used_at,
          b.dropoff_qr_token_hash,
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
          lo.code AS origin_location_code,
          ld.code AS destination_location_code,
          EXISTS (
            SELECT 1
            FROM booking_charge_items bci
            WHERE bci.booking_id = b.id
              AND bci.charge_type = 'NAME_SIGN'
              AND bci.deleted_at IS NULL
            LIMIT 1
          ) AS name_sign_requested,
          EXISTS (
            SELECT 1
            FROM booking_driver_assignments released_bda
            WHERE released_bda.booking_id = b.id
              AND released_bda.is_active = 0
              AND released_bda.deleted_at IS NULL
              AND released_bda.assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
            LIMIT 1
          ) AS has_driver_release_history,
          d.name AS driver_name,
          d.phone AS driver_phone,
          dv.plate_number AS assigned_vehicle_plate,
          dv.model_name AS assigned_vehicle_model,
          dv.color AS assigned_vehicle_color,
          av.code AS assigned_vehicle_type_code,
          av.name AS assigned_vehicle_type_name,
          (
            SELECT f.id
            FROM driver_applications da
            INNER JOIN driver_application_files daf
              ON daf.driver_application_id = da.id
             AND daf.category = 'DRIVER_VEHICLE_PHOTO'
            INNER JOIN files f
              ON f.id = daf.file_id
             AND f.deleted_at IS NULL
            WHERE da.approved_driver_id = d.id
              AND da.status = 'APPROVED'
              AND da.deleted_at IS NULL
            ORDER BY daf.sort_order ASC, f.id ASC
            LIMIT 1
          ) AS driver_vehicle_photo_file_id
        FROM bookings b
        INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
        INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
        LEFT JOIN routes r ON r.id = b.route_id AND r.deleted_at IS NULL
        LEFT JOIN locations lo ON lo.id = r.origin_location_id AND lo.deleted_at IS NULL
        LEFT JOIN locations ld ON ld.id = r.destination_location_id AND ld.deleted_at IS NULL
        LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
        LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
        LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
        LEFT JOIN booking_driver_assignments bda ON bda.id = (
          SELECT bda2.id
          FROM booking_driver_assignments bda2
          WHERE bda2.booking_id = b.id
            AND bda2.deleted_at IS NULL
            AND (
              bda2.is_active = 1
              OR b.status IN ('SETTLEMENT_PENDING', 'COMPLETED')
            )
          ORDER BY bda2.is_active DESC, bda2.updated_at DESC, bda2.id DESC
          LIMIT 1
        )
        LEFT JOIN drivers d ON d.id = COALESCE(bda.driver_id, b.driver_id) AND d.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.id = bda.driver_vehicle_id AND dv.deleted_at IS NULL
        LEFT JOIN vehicle_types av ON av.id = dv.vehicle_type_id AND av.deleted_at IS NULL
        WHERE b.booking_number = ? AND b.deleted_at IS NULL AND b.is_archived = 0
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] || null;
  }

  async findByBookingNumberForUpdate(conn, bookingNumber) {
    const [rows] = await conn.query(
      `
        SELECT
          b.id, b.booking_number, b.status, b.total_amount, b.currency, b.vehicle_type_id,
          b.scheduled_pickup_at,
          b.payment_status, b.payment_method, b.customer_user_id,
          b.is_urgent_request,
          b.urgent_negotiation_id,
          COALESCE(b.driver_id, bda.driver_id) AS driver_id,
          b.dropoff_qr_token_hash, b.dropoff_qr_expires_at, b.dropoff_qr_used_at,
          d.user_id AS driver_user_id,
          st.code AS service_type_code,
          btd.flight_scheduled_arrival_at,
          DATE_FORMAT(btd.flight_scheduled_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_scheduled_arrival_at_text,
          btd.flight_estimated_arrival_at,
          DATE_FORMAT(btd.flight_estimated_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_estimated_arrival_at_text
        FROM bookings b
        INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
        LEFT JOIN booking_driver_assignments bda ON bda.id = (
          SELECT bda2.id
          FROM booking_driver_assignments bda2
          WHERE bda2.booking_id = b.id
            AND bda2.deleted_at IS NULL
            AND (
              bda2.is_active = 1
              OR b.status IN ('SETTLEMENT_PENDING', 'COMPLETED')
            )
          ORDER BY bda2.is_active DESC, bda2.updated_at DESC, bda2.id DESC
          LIMIT 1
        )
        LEFT JOIN drivers d ON d.id = COALESCE(b.driver_id, bda.driver_id) AND d.deleted_at IS NULL
        LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
        WHERE b.booking_number = ? AND b.deleted_at IS NULL AND b.is_archived = 0
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

  async findGuestAssignedDriverVehiclePhotoFile(bookingId, tokenHash) {
    const [rows] = await this.pool.query(
      `
        SELECT
          f.file_path,
          f.mime_type,
          f.original_filename
        FROM bookings b
        INNER JOIN guest_access_tokens gat ON gat.booking_id = b.id
          AND gat.token_hash = ?
          AND gat.revoked_at IS NULL
          AND gat.expires_at > CURRENT_TIMESTAMP
        INNER JOIN booking_driver_assignments bda ON bda.booking_id = b.id
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
        INNER JOIN drivers d ON d.id = bda.driver_id
          AND d.deleted_at IS NULL
        INNER JOIN driver_applications da ON da.approved_driver_id = d.id
          AND da.status = 'APPROVED'
          AND da.deleted_at IS NULL
        INNER JOIN driver_application_files daf ON daf.driver_application_id = da.id
          AND daf.category = 'DRIVER_VEHICLE_PHOTO'
        INNER JOIN files f ON f.id = daf.file_id
          AND f.deleted_at IS NULL
        WHERE b.id = ?
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        ORDER BY daf.sort_order ASC, f.id ASC
        LIMIT 1
      `,
      [tokenHash, bookingId],
    );
    return rows[0] || null;
  }

  driverJobSelectCoreSql() {
    return `
      SELECT
        b.id,
        b.booking_number,
        b.status,
        bda.status AS assignment_status,
        bda.accepted_at,
        b.scheduled_pickup_at,
        DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d') AS pickup_date,
        DATE_FORMAT(b.scheduled_pickup_at, '%H:%i') AS pickup_time,
        b.origin_address,
        b.origin_place_id,
        b.origin_lat,
        b.origin_lng,
        b.destination_address,
        b.destination_place_id,
        b.destination_lat,
        b.destination_lng,
        b.metadata,
        b.customer_name,
        b.customer_phone,
        b.special_requests,
        b.total_amount,
        b.currency,
        b.commission_amount,
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
        btd.flight_scheduled_arrival_at,
        DATE_FORMAT(btd.flight_scheduled_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_scheduled_arrival_at_text,
        btd.flight_estimated_arrival_at,
        DATE_FORMAT(btd.flight_estimated_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_estimated_arrival_at_text,
        btd.delay_status,
        btd.delay_minutes,
        EXISTS (
          SELECT 1
          FROM booking_charge_items bci
          WHERE bci.booking_id = b.id
            AND bci.charge_type = 'NAME_SIGN'
            AND bci.deleted_at IS NULL
          LIMIT 1
        ) AS name_sign_requested
      FROM booking_driver_assignments bda
      INNER JOIN drivers d ON d.id = bda.driver_id AND d.deleted_at IS NULL
      INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
      INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
      INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
      LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
      LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
      LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
    `;
  }

  driverJobActiveWhereSql() {
    return `
      WHERE
        d.user_id = ?
        AND d.is_active = 1
        AND bda.is_active = 1
        AND bda.deleted_at IS NULL
        AND bda.status IN ('ASSIGNED', 'ACCEPTED')
        AND b.is_archived = 0
    `;
  }

  driverJobSelectSql() {
    return `${this.driverJobSelectCoreSql()}${this.driverJobActiveWhereSql()}`;
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

  async findActiveDriverBookingsScheduled(driverUserId) {
    const [rows] = await this.pool.query(
      `
        ${this.driverJobSelectSql()}
        AND b.status NOT IN ('CANCELLED', 'COMPLETED', 'NO_SHOW')
        ORDER BY
          CASE
            WHEN b.status IN ('ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING') THEN 0
            ELSE 1
          END ASC,
          b.scheduled_pickup_at ASC,
          b.booking_number ASC
      `,
      [driverUserId],
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

  async findDriverTerminalBookingByNumber(driverUserId, bookingNumber) {
    const [rows] = await this.pool.query(
      `
        ${this.driverJobSelectCoreSql()}
        WHERE
          d.user_id = ?
          AND d.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status = 'COMPLETED'
          AND b.status IN ('COMPLETED', 'CANCELLED', 'NO_SHOW')
          AND b.booking_number = ?
          AND b.is_archived = 0
        LIMIT 1
      `,
      [driverUserId, bookingNumber],
    );
    return rows[0] || null;
  }

  /**
   * Returns the latest inactive/active assignment link for this driver+booking,
   * only when the driver previously had an assignment. Used to explain why detail
   * is no longer available without leaking existence to unrelated drivers.
   */
  async findDriverAssignmentAccessOutcome(driverUserId, bookingNumber) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id AS booking_id,
          b.booking_number,
          b.status AS booking_status,
          my_bda.id AS assignment_id,
          my_bda.status AS assignment_status,
          my_bda.is_active AS assignment_is_active,
          my_bda.assignment_reason,
          my_bda.unassigned_at,
          EXISTS (
            SELECT 1
            FROM booking_driver_assignments other_bda
            WHERE other_bda.booking_id = b.id
              AND other_bda.deleted_at IS NULL
              AND other_bda.is_active = 1
              AND other_bda.driver_id <> my_bda.driver_id
            LIMIT 1
          ) AS has_other_active_assignment
        FROM bookings b
        INNER JOIN booking_driver_assignments my_bda
          ON my_bda.booking_id = b.id
         AND my_bda.deleted_at IS NULL
        INNER JOIN drivers d
          ON d.id = my_bda.driver_id
         AND d.deleted_at IS NULL
         AND d.user_id = ?
        WHERE b.booking_number = ?
          AND b.deleted_at IS NULL
        ORDER BY
          my_bda.assigned_at DESC,
          my_bda.id DESC
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

  openDriverCallSelectSql() {
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
        b.total_amount,
        b.currency,
        b.commission_amount,
        b.payment_method,
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
        b.is_urgent_request,
        b.urgent_negotiation_id,
        bun.min_required_eta_minutes AS urgent_min_required_eta_minutes
      FROM bookings b
      INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
      INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
      LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
      LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
      LEFT JOIN booking_urgent_negotiations bun ON bun.id = b.urgent_negotiation_id
        AND bun.status = 'BROADCASTING'
    `;
  }

  async findOpenDriverCallsForDriver(driverUserId) {
    const [rows] = await this.pool.query(
      `
        ${this.openDriverCallSelectSql()}
        INNER JOIN drivers d ON d.user_id = ?
          AND d.deleted_at IS NULL
          AND d.is_active = 1
          AND d.is_online = 1
          AND d.status = 'AVAILABLE'
        INNER JOIN users u ON u.id = d.user_id
          AND u.role = 'DRIVER'
          AND u.is_active = 1
          AND u.deleted_at IS NULL
        WHERE b.deleted_at IS NULL
          AND b.is_archived = 0
          AND b.status = 'OPEN'
          AND EXISTS (
            SELECT 1
            FROM driver_vehicles dv
            WHERE dv.driver_id = d.id
              AND dv.vehicle_type_id = b.vehicle_type_id
              AND dv.is_active = 1
              AND dv.deleted_at IS NULL
          )
          AND NOT EXISTS (
            SELECT 1
            FROM booking_driver_assignments active_bda
            WHERE active_bda.booking_id = b.id
              AND active_bda.is_active = 1
              AND active_bda.deleted_at IS NULL
          )
          AND NOT EXISTS (
            SELECT 1
            FROM booking_driver_assignments released_bda
            WHERE released_bda.booking_id = b.id
              AND released_bda.driver_id = d.id
              AND released_bda.is_active = 0
              AND released_bda.deleted_at IS NULL
              AND released_bda.assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
              AND released_bda.unassigned_at > (UTC_TIMESTAMP() - INTERVAL 30 MINUTE)
          )
          AND NOT EXISTS (
            SELECT 1
            FROM booking_driver_assignments own_bda
            INNER JOIN bookings own_b ON own_b.id = own_bda.booking_id AND own_b.deleted_at IS NULL AND own_b.is_archived = 0
            WHERE own_bda.driver_id = d.id
              AND own_bda.is_active = 1
              AND own_bda.deleted_at IS NULL
              AND own_bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND own_b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING')
          )
        ORDER BY b.created_at DESC, b.scheduled_pickup_at ASC, b.booking_number ASC
      `,
      [driverUserId],
    );
    return rows;
  }

  async findOpenDriverCallByBookingId(conn, bookingId) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        ${this.openDriverCallSelectSql()}
        WHERE b.id = ?
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
          AND b.status = 'OPEN'
        LIMIT 1
      `,
      [bookingId],
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
          AND is_archived = 0
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

  async setBoardingQr(conn, bookingId, tokenHash, expiresAt) {
    await conn.query(
      `
        UPDATE bookings
        SET
          boarding_qr_token_hash = ?,
          boarding_qr_expires_at = ?,
          boarding_qr_used_at = NULL
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

  async reopenAfterDriverRelease(conn, bookingId, actorUserId) {
    await conn.query(
      `
        UPDATE bookings
        SET
          status = 'OPEN',
          driver_id = NULL,
          updated_by = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [actorUserId, bookingId],
    );
  }

  async updateUrgentNegotiationId(conn, bookingId, negotiationId) {
    await conn.query(
      `
        UPDATE bookings
        SET
          urgent_negotiation_id = ?,
          updated_at = CURRENT_TIMESTAMP(3)
        WHERE id = ?
          AND deleted_at IS NULL
      `,
      [negotiationId, bookingId],
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

  buildAdminUnreadExistsSql(adminUserId) {
    if (!adminUserId) return { sql: '0', params: [] };
    return {
      sql: `
        EXISTS (
          SELECT 1
          FROM chat_rooms cr
          INNER JOIN chat_participants ap ON ap.chat_room_id = cr.id
            AND ap.user_id = ?
            AND ap.participant_role = 'ADMIN'
            AND ap.deleted_at IS NULL
          INNER JOIN chat_messages m ON m.chat_room_id = cr.id
            AND m.deleted_at IS NULL
            AND m.sender_participant_id <> ap.id
            AND (ap.last_read_at IS NULL OR m.created_at > ap.last_read_at)
          WHERE cr.booking_id = b.id
            AND cr.deleted_at IS NULL
        )
      `,
      params: [adminUserId],
    };
  }

  buildNeedsActionWhere(filters) {
    const where = [];
    const params = [];
    const nowText = filters.operationsNow;
    const urgentCutoff = filters.operationsUrgentCutoff;
    const unread = this.buildAdminUnreadExistsSql(filters.adminUserId);

    where.push(this.buildLowRatingExistsSql());

    where.push(`
      (
        b.status = 'SETTLEMENT_PENDING'
        AND b.commission_status IN ('DUE', 'OVERDUE')
        AND JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) IS NOT NULL
        AND b.commission_receipt_file_id IS NULL
      )
    `);

    where.push(`
      (
        b.status = 'SETTLEMENT_PENDING'
        AND b.commission_status IN ('DUE', 'OVERDUE')
        AND b.commission_receipt_file_id IS NOT NULL
      )
    `);

    where.push(`
      (
        b.status = 'SETTLEMENT_PENDING'
        AND b.commission_status IN ('DUE', 'OVERDUE')
        AND b.commission_receipt_file_id IS NULL
        AND (
          JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) IS NULL
          OR JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) = ''
        )
      )
    `);

    where.push(`
      (
        ${this.unassignedBookingSql()}
        AND b.scheduled_pickup_at <= ?
      )
    `);
    params.push(urgentCutoff);

    where.push(`
      (
        b.scheduled_pickup_at < ?
        AND b.status IN ('PENDING', 'CONFIRMED', 'DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED')
      )
    `);
    params.push(nowText);

    where.push(`
      (
        b.status = 'DRIVER_ARRIVED'
        AND b.updated_at < DATE_SUB(?, INTERVAL 30 MINUTE)
      )
    `);
    params.push(nowText);

    where.push(`
      (
        b.status = 'PICKED_UP'
        AND b.updated_at < DATE_SUB(?, INTERVAL 6 HOUR)
      )
    `);
    params.push(nowText);

    where.push(`
      (
        b.status NOT IN ('COMPLETED', 'CANCELLED', 'NO_SHOW', 'SETTLEMENT_PENDING')
        AND b.updated_at < DATE_SUB(?, INTERVAL 2 HOUR)
      )
    `);
    params.push(nowText);

    if (filters.adminUserId) {
      where.push(`(${unread.sql})`);
      params.push(...unread.params);
    }

    return { sql: `(${where.join(' OR ')})`, params };
  }

  buildLowRatingExistsSql() {
    return `EXISTS (
      SELECT 1 FROM reviews r
      WHERE r.booking_id = b.id
        AND r.rating <= 2
    )`;
  }

  buildIssuesWhere(filters) {
    const where = [];
    const params = [];
    const nowText = filters.operationsNow;
    const unread = this.buildAdminUnreadExistsSql(filters.adminUserId);

    where.push(this.buildLowRatingExistsSql());

    where.push(`
      (
        b.status = 'SETTLEMENT_PENDING'
        AND b.commission_status IN ('DUE', 'OVERDUE')
        AND JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) IS NOT NULL
        AND b.commission_receipt_file_id IS NULL
      )
    `);

    where.push(`
      (
        ${this.unassignedBookingSql()}
        AND b.scheduled_pickup_at < ?
      )
    `);
    params.push(nowText);

    where.push(`
      (
        b.scheduled_pickup_at < ?
        AND b.status IN ('PENDING', 'CONFIRMED', 'DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED')
      )
    `);
    params.push(nowText);

    where.push(`
      (
        b.status = 'DRIVER_ARRIVED'
        AND b.updated_at < DATE_SUB(?, INTERVAL 30 MINUTE)
      )
    `);
    params.push(nowText);

    where.push(`
      (
        b.status = 'PICKED_UP'
        AND b.updated_at < DATE_SUB(?, INTERVAL 6 HOUR)
      )
    `);
    params.push(nowText);

    if (filters.adminUserId) {
      where.push(`(${unread.sql})`);
      params.push(...unread.params);
    }

    return { sql: `(${where.join(' OR ')})`, params };
  }

  buildAdminBookingFilters(filters) {
    const where = ['b.deleted_at IS NULL'];
    const params = [];

    if (filters.archivedOnly) {
      where.push('b.is_archived = 1');
    } else if (!filters.includeArchived) {
      where.push('b.is_archived = 0');
    }

    if (filters.status) {
      where.push('b.status = ?');
      params.push(filters.status);
    }

    if (Array.isArray(filters.statuses) && filters.statuses.length) {
      where.push(`b.status IN (${filters.statuses.map(() => '?').join(', ')})`);
      params.push(...filters.statuses);
    }

    if (filters.cancelledTab) {
      where.push(`b.status IN ('CANCELLED', 'NO_SHOW')`);
    }

    if (filters.excludeTerminalStatuses) {
      where.push(`b.status NOT IN ('COMPLETED', 'CANCELLED', 'NO_SHOW')`);
    }

    if (filters.inProgressOnly) {
      where.push(`b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP')`);
    }

    if (filters.needsActionOnly) {
      const needsAction = this.buildNeedsActionWhere(filters);
      where.push(needsAction.sql);
      params.push(...needsAction.params);
    }

    if (filters.issuesOnly) {
      const issues = this.buildIssuesWhere(filters);
      where.push(issues.sql);
      params.push(...issues.params);
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

    if (filters.serviceType) {
      where.push('st.code = ?');
      params.push(filters.serviceType);
    }

    if (filters.origin) {
      where.push('b.origin_address LIKE ?');
      params.push(`%${filters.origin}%`);
    }

    if (filters.destination) {
      where.push('b.destination_address LIKE ?');
      params.push(`%${filters.destination}%`);
    }

    if (filters.lowRating) {
      where.push(this.buildLowRatingExistsSql());
    }

    if (filters.unassigned) {
      where.push(this.unassignedBookingSql());
    }

    if (filters.hasInquiry && filters.adminUserId) {
      const unread = this.buildAdminUnreadExistsSql(filters.adminUserId);
      where.push(`(${unread.sql})`);
      params.push(...unread.params);
    }

    if (filters.settlementStatus === 'RECEIPT_REJECTED') {
      where.push(`
        b.status = 'SETTLEMENT_PENDING'
        AND JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) IS NOT NULL
        AND b.commission_receipt_file_id IS NULL
      `);
    } else if (filters.settlementStatus === 'RECEIPT_SUBMITTED') {
      where.push(`
        b.status = 'SETTLEMENT_PENDING'
        AND b.commission_receipt_file_id IS NOT NULL
        AND b.commission_status IN ('DUE', 'OVERDUE')
      `);
    } else if (filters.settlementStatus === 'RECEIPT_MISSING') {
      where.push(`
        b.status = 'SETTLEMENT_PENDING'
        AND b.commission_receipt_file_id IS NULL
        AND (
          JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) IS NULL
          OR JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) = ''
        )
      `);
    } else if (filters.settlementStatus === 'ADMIN_CONFIRMED') {
      where.push(`b.commission_status = 'PAID'`);
    }

    if (filters.assignmentState === 'ASSIGNED') {
      where.push(this.activeAssignmentExistsSql());
    } else if (filters.assignmentState === 'UNASSIGNED') {
      where.push(this.activeAssignmentMissingSql());
    }

    if (filters.search) {
      const term = `%${filters.search}%`;
      where.push(`
        (
          b.booking_number LIKE ?
          OR b.customer_name LIKE ?
          OR b.customer_phone LIKE ?
          OR b.customer_email LIKE ?
          OR b.origin_address LIKE ?
          OR b.destination_address LIKE ?
          OR btd.flight_number LIKE ?
          OR d.name LIKE ?
          OR d.phone LIKE ?
          OR dv.plate_number LIKE ?
        )
      `);
      params.push(term, term, term, term, term, term, term, term, term, term);
    }

    return { whereSql: where.join(' AND '), params };
  }

  adminQueueFromSql(adminUserId = null) {
    return `
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
      LEFT JOIN driver_vehicles dv ON dv.id = bda.driver_vehicle_id AND dv.deleted_at IS NULL
      LEFT JOIN vehicle_types av ON av.id = dv.vehicle_type_id AND av.deleted_at IS NULL
      LEFT JOIN (
        SELECT cr.booking_id, COUNT(m.id) AS admin_unread_count
        FROM chat_rooms cr
        INNER JOIN chat_participants ap ON ap.chat_room_id = cr.id
          AND ap.user_id = ?
          AND ap.participant_role = 'ADMIN'
          AND ap.deleted_at IS NULL
        INNER JOIN chat_messages m ON m.chat_room_id = cr.id
          AND m.deleted_at IS NULL
          AND m.sender_participant_id <> ap.id
          AND (ap.last_read_at IS NULL OR m.created_at > ap.last_read_at)
        WHERE cr.deleted_at IS NULL
        GROUP BY cr.booking_id
      ) chat_unread ON chat_unread.booking_id = b.id
    `;
  }

  adminQueueSelectSql(adminUserId = null) {
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
        b.updated_at,
        b.driver_id,
        b.commission_status,
        b.commission_receipt_file_id,
        b.metadata,
        b.is_archived,
        b.archived_at,
        b.archived_by,
        b.archive_reason,
        CASE WHEN ${this.activeAssignmentMissingSql()} THEN 1 ELSE 0 END AS is_new_booking,
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
        (
          SELECT r.rating
          FROM reviews r
          WHERE r.booking_id = b.id
          ORDER BY r.id DESC
          LIMIT 1
        ) AS review_rating,
        COALESCE(chat_unread.admin_unread_count, 0) AS admin_unread_count,
        bda.id AS assignment_id,
        bda.driver_id AS assignment_driver_id,
        bda.status AS assignment_status,
        d.name AS driver_name,
        d.phone AS driver_phone,
        d.status AS driver_status,
        dv.plate_number AS assigned_vehicle_plate,
        dv.model_name AS assigned_vehicle_model,
        av.code AS assigned_vehicle_type_code,
        av.name AS assigned_vehicle_type_name,
        (
          SELECT rbda.unassigned_at
          FROM booking_driver_assignments rbda
          WHERE rbda.booking_id = b.id
            AND rbda.is_active = 0
            AND rbda.deleted_at IS NULL
            AND rbda.assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
          ORDER BY rbda.unassigned_at DESC, rbda.id DESC
          LIMIT 1
        ) AS last_driver_release_at,
        (
          SELECT rd.name
          FROM booking_driver_assignments rbda
          INNER JOIN drivers rd ON rd.id = rbda.driver_id AND rd.deleted_at IS NULL
          WHERE rbda.booking_id = b.id
            AND rbda.is_active = 0
            AND rbda.deleted_at IS NULL
            AND rbda.assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
          ORDER BY rbda.unassigned_at DESC, rbda.id DESC
          LIMIT 1
        ) AS last_released_driver_name,
        (
          SELECT JSON_UNQUOTE(JSON_EXTRACT(bal.payload, '$.reasonCode'))
          FROM booking_activity_logs bal
          WHERE bal.booking_id = b.id
            AND bal.activity_type = 'DRIVER_RELEASED_ASSIGNMENT'
          ORDER BY bal.id DESC
          LIMIT 1
        ) AS last_driver_release_reason_code
      ${this.adminQueueFromSql(adminUserId)}
    `;
  }

  adminQueueOrderSql(view) {
    if (view === 'needs_action') {
      return `
        ORDER BY
          b.scheduled_pickup_at ASC,
          b.booking_number ASC
      `;
    }
    if (view === 'issues') {
      return `
        ORDER BY
          b.scheduled_pickup_at ASC,
          b.booking_number ASC
      `;
    }
    if (view === 'settlement') {
      return `
        ORDER BY
          CASE
            WHEN b.status = 'SETTLEMENT_PENDING'
              AND JSON_UNQUOTE(JSON_EXTRACT(b.metadata, '$.commissionRejectionReason')) IS NOT NULL
              AND b.commission_receipt_file_id IS NULL THEN 0
            WHEN b.commission_receipt_file_id IS NOT NULL
              AND b.commission_status IN ('DUE', 'OVERDUE') THEN 1
            WHEN b.status = 'SETTLEMENT_PENDING'
              AND b.commission_receipt_file_id IS NULL THEN 2
            WHEN b.commission_status = 'PAID' THEN 3
            ELSE 4
          END ASC,
          b.scheduled_pickup_at DESC,
          b.booking_number DESC
      `;
    }
    return `
      ORDER BY
        CASE WHEN ${this.activeAssignmentMissingSql()} THEN 0 ELSE 1 END ASC,
        CASE WHEN ${this.activeAssignmentMissingSql()} THEN b.created_at END DESC,
        CASE WHEN ${this.activeAssignmentExistsSql()} THEN b.scheduled_pickup_at END DESC,
        b.booking_number DESC
    `;
  }

  async countAdminUnreadForBooking(adminUserId, bookingId) {
    if (!adminUserId) return 0;
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(m.id) AS unread_count
        FROM chat_rooms cr
        INNER JOIN chat_participants ap ON ap.chat_room_id = cr.id
          AND ap.user_id = ?
          AND ap.participant_role = 'ADMIN'
          AND ap.deleted_at IS NULL
        INNER JOIN chat_messages m ON m.chat_room_id = cr.id
          AND m.deleted_at IS NULL
          AND m.sender_participant_id <> ap.id
          AND (ap.last_read_at IS NULL OR m.created_at > ap.last_read_at)
        WHERE cr.booking_id = ?
          AND cr.deleted_at IS NULL
      `,
      [adminUserId, bookingId],
    );
    return Number(rows[0]?.unread_count ?? 0);
  }

  async countAdminBookings(filters) {
    const { whereSql, params } = this.buildAdminBookingFilters(filters);
    const adminUserId = filters.adminUserId ?? null;
    const fromParams = adminUserId ? [adminUserId] : [0];
    const [rows] = await this.pool.query(
      `
        SELECT COUNT(DISTINCT b.id) AS total
        ${this.adminQueueFromSql(adminUserId)}
        WHERE ${whereSql}
      `,
      [...fromParams, ...params],
    );
    return rows[0]?.total ?? 0;
  }

  async findAdminBookings(filters, pagination) {
    const { whereSql, params } = this.buildAdminBookingFilters(filters);
    const limit = pagination.limit;
    const offset = pagination.offset;
    const adminUserId = filters.adminUserId ?? null;
    const fromParams = adminUserId ? [adminUserId] : [0];
    const orderSql = this.adminQueueOrderSql(filters.view);

    const [rows] = await this.pool.query(
      `
        ${this.adminQueueSelectSql(adminUserId)}
        WHERE ${whereSql}
        ${orderSql}
        LIMIT ? OFFSET ?
      `,
      [...fromParams, ...params, limit, offset],
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
          b.is_archived,
          b.archived_at,
          b.archived_by,
          b.archive_reason,
          b.boarding_qr_token_hash,
          b.boarding_qr_used_at,
          b.dropoff_qr_token_hash,
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
          d.phone AS driver_phone,
          d.status AS driver_status,
          dv.plate_number AS vehicle_plate,
          dv.model_name AS vehicle_model,
          vt.code AS vehicle_type_code,
          vt.name AS vehicle_type_name
        FROM booking_driver_assignments bda
        LEFT JOIN drivers d ON d.id = bda.driver_id AND d.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.id = bda.driver_vehicle_id AND dv.deleted_at IS NULL
        LEFT JOIN vehicle_types vt ON vt.id = dv.vehicle_type_id AND vt.deleted_at IS NULL
        WHERE bda.booking_id = ? AND bda.deleted_at IS NULL
        ORDER BY bda.assigned_at DESC, bda.id DESC
      `,
      [bookingId],
    );
    return rows;
  }

  async findBookingForDriverCandidates(bookingNumber) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.status,
          b.vehicle_type_id,
          b.origin_lat,
          b.origin_lng,
          b.scheduled_pickup_at,
          vt.code AS vehicle_type_code
        FROM bookings b
        INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
        WHERE b.booking_number = ? AND b.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingNumber],
    );
    return rows[0] || null;
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
          bda.assignment_reason,
          bda.accepted_at
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

  async acceptDriverAssignment(conn, assignmentId) {
    const [result] = await conn.query(
      `
        UPDATE booking_driver_assignments
        SET
          status = 'ACCEPTED',
          accepted_at = COALESCE(accepted_at, CURRENT_TIMESTAMP),
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND status = 'ASSIGNED'
          AND is_active = 1
          AND deleted_at IS NULL
      `,
      [assignmentId],
    );
    if (result.affectedRows !== 1) return null;

    const [rows] = await conn.query(
      `
        SELECT id, driver_id, status, accepted_at
        FROM booking_driver_assignments
        WHERE id = ?
          AND is_active = 1
          AND deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [assignmentId],
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

  async hasReleasedAssignment(conn, bookingId, driverId, { withinCooldown = true } = {}) {
    const executor = conn ?? this.pool;
    // Exclusive 30m boundary: at exactly 30 minutes the same driver may see/claim again.
    const cooldownSql = withinCooldown
      ? 'AND bda.unassigned_at > (UTC_TIMESTAMP() - INTERVAL 30 MINUTE)'
      : '';
    const [rows] = await executor.query(
      `
        SELECT 1
        FROM booking_driver_assignments bda
        WHERE bda.booking_id = ?
          AND bda.driver_id = ?
          AND bda.is_active = 0
          AND bda.deleted_at IS NULL
          AND bda.assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
          ${cooldownSql}
        LIMIT 1
      `,
      [bookingId, driverId],
    );
    return rows.length > 0;
  }

  async completeActiveAssignment(conn, bookingId) {
    await conn.query(
      `
        UPDATE booking_driver_assignments
        SET
          is_active = 0,
          status = 'COMPLETED',
          completed_at = CURRENT_TIMESTAMP,
          unassigned_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
        WHERE booking_id = ?
          AND is_active = 1
          AND deleted_at IS NULL
      `,
      [bookingId],
    );
  }

  async clearAssignmentOnCancel(conn, bookingId, actorUserId, reason = 'CUSTOMER_CANCELLED') {
    const active = await this.findActiveAssignmentForUpdate(conn, bookingId);
    if (active) {
      await this.deactivateAssignment(conn, active.id, reason);
    }
    await conn.query(
      `
        UPDATE bookings
        SET
          driver_id = NULL,
          updated_by = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND deleted_at IS NULL
      `,
      [actorUserId ?? null, bookingId],
    );
    return active || null;
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
        DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d') AS pickup_date,
        DATE_FORMAT(b.scheduled_pickup_at, '%H:%i') AS pickup_time,
        b.origin_address,
        b.destination_address,
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
          AND b.is_archived = 0
          AND b.status IN (${SETTLEMENT_ELIGIBLE_BOOKING_STATUSES_SQL})
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
          AND b.status IN (${SETTLEMENT_ELIGIBLE_BOOKING_STATUSES_SQL})
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
          AND b.commission_status NOT IN ('NOT_DUE_YET', 'WAIVED')
        GROUP BY b.id
        ORDER BY COALESCE(b.completed_at, b.updated_at) DESC, b.booking_number DESC
      `,
      [driverId],
    );
    return rows;
  }

  buildAdminSettlementFilters(filters) {
    const where = [
      'b.deleted_at IS NULL',
      'b.is_archived = 0',
      `b.status IN (${SETTLEMENT_ELIGIBLE_BOOKING_STATUSES_SQL})`,
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
    } else {
      where.push('b.commission_status <> \'PAID\'');
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
        ORDER BY COALESCE(b.completed_at, b.updated_at) DESC, b.booking_number DESC
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
          AND b.is_archived = 0
          AND b.status IN (${SETTLEMENT_ELIGIBLE_BOOKING_STATUSES_SQL})
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
      'b.is_archived = 0',
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
          AND b.is_archived = 0
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
          AND b.is_archived = 0
          AND b.status IN (${SETTLEMENT_ELIGIBLE_BOOKING_STATUSES_SQL})
          AND b.commission_status NOT IN ('PAID', 'WAIVED', 'NOT_DUE_YET')
      `,
      [driverId],
    );
    return rows;
  }

  async findArchiveCandidatesForUpdate(conn, bookingNumbers) {
    if (!bookingNumbers.length) return [];
    const placeholders = bookingNumbers.map(() => '?').join(', ');
    const [rows] = await conn.query(
      `
        SELECT
          b.id,
          b.booking_number,
          b.status,
          b.commission_status,
          b.completed_at,
          b.is_archived,
          b.archive_reason,
          EXISTS (
            SELECT 1
            FROM booking_driver_assignments bda
            WHERE bda.booking_id = b.id
              AND bda.deleted_at IS NULL
            LIMIT 1
          ) AS has_assignment,
          EXISTS (
            SELECT 1
            FROM booking_status_logs bsl
            WHERE bsl.booking_id = b.id
              AND (
                bsl.to_status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING', 'COMPLETED')
                OR bsl.from_status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING', 'COMPLETED')
              )
            LIMIT 1
          ) AS has_trip_status_log
        FROM bookings b
        WHERE b.booking_number IN (${placeholders})
          AND b.deleted_at IS NULL
        FOR UPDATE
      `,
      bookingNumbers,
    );
    return rows;
  }

  async archiveBookings(conn, bookingIds, { actorUserId, reason }) {
    if (!bookingIds.length) return 0;
    const placeholders = bookingIds.map(() => '?').join(', ');
    const [result] = await conn.query(
      `
        UPDATE bookings
        SET
          is_archived = 1,
          archived_at = CURRENT_TIMESTAMP,
          archived_by = ?,
          archive_reason = ?,
          updated_by = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id IN (${placeholders})
          AND deleted_at IS NULL
      `,
      [actorUserId, reason, actorUserId, ...bookingIds],
    );
    return result.affectedRows;
  }

  async restoreBookings(conn, bookingIds, { actorUserId }) {
    if (!bookingIds.length) return 0;
    const placeholders = bookingIds.map(() => '?').join(', ');
    const [result] = await conn.query(
      `
        UPDATE bookings
        SET
          is_archived = 0,
          archived_at = NULL,
          archived_by = NULL,
          archive_reason = NULL,
          updated_by = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE id IN (${placeholders})
          AND deleted_at IS NULL
      `,
      [actorUserId, ...bookingIds],
    );
    return result.affectedRows;
  }
}

module.exports = BookingRepository;
