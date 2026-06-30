const database = require('../config/database');
const SERVICE_TYPES = require('../constants/serviceTypes');

class FlightMonitorRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  buildListWhere(filters) {
    const where = [
      'b.deleted_at IS NULL',
      'btd.deleted_at IS NULL',
      'st.deleted_at IS NULL',
      "st.code = ?",
      'btd.flight_number IS NOT NULL',
      "TRIM(btd.flight_number) <> ''",
    ];
    const params = [SERVICE_TYPES.AIRPORT_PICKUP];

    if (filters.date) {
      where.push('(DATE(b.scheduled_pickup_at) = ? OR btd.flight_date = ?)');
      params.push(filters.date, filters.date);
    }

    if (filters.flightNumber) {
      where.push('btd.flight_number = ?');
      params.push(filters.flightNumber);
    }

    if (filters.bookingNumber) {
      where.push('b.booking_number = ?');
      params.push(filters.bookingNumber);
    }

    if (filters.status) {
      where.push('btd.flight_status = ?');
      params.push(filters.status);
    }

    if (filters.delayedOnly) {
      where.push('btd.delay_minutes > 0');
    }

    return { whereSql: where.join(' AND '), params };
  }

  async listFlights(filters, pagination) {
    const { whereSql, params } = this.buildListWhere(filters);
    const offset = (pagination.page - 1) * pagination.pageSize;

    const [countRows] = await this.pool.query(
      `
        SELECT COUNT(*) AS total
        FROM bookings b
        INNER JOIN booking_transfer_details btd ON btd.booking_id = b.id
        INNER JOIN service_types st ON st.id = b.service_type_id
        WHERE ${whereSql}
      `,
      params,
    );

    const [rows] = await this.pool.query(
      `
        SELECT
          b.id AS booking_id,
          b.booking_number,
          b.status AS booking_status,
          b.scheduled_pickup_at,
          DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d %H:%i:%s') AS scheduled_pickup_at_text,
          btd.flight_number,
          btd.airline_code,
          btd.flight_date,
          btd.departure_airport_iata,
          btd.arrival_airport_iata,
          btd.flight_scheduled_arrival_at,
          DATE_FORMAT(btd.flight_scheduled_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_scheduled_arrival_at_text,
          btd.flight_estimated_arrival_at,
          DATE_FORMAT(btd.flight_estimated_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_estimated_arrival_at_text,
          btd.flight_actual_arrival_at,
          DATE_FORMAT(btd.flight_actual_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_actual_arrival_at_text,
          btd.delay_minutes,
          btd.delay_status,
          btd.flight_status,
          btd.last_synced_at,
          DATE_FORMAT(btd.last_synced_at, '%Y-%m-%d %H:%i:%s') AS last_synced_at_text,
          btd.sync_status,
          btd.sync_error
        FROM bookings b
        INNER JOIN booking_transfer_details btd ON btd.booking_id = b.id
        INNER JOIN service_types st ON st.id = b.service_type_id
        WHERE ${whereSql}
        ORDER BY b.scheduled_pickup_at ASC, b.id ASC
        LIMIT ? OFFSET ?
      `,
      [...params, pagination.pageSize, offset],
    );

    return {
      total: Number(countRows[0]?.total ?? 0),
      rows,
    };
  }

  async findFlightBookingById(bookingId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id AS booking_id,
          b.booking_number,
          b.status AS booking_status,
          b.scheduled_pickup_at,
          DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d %H:%i:%s') AS scheduled_pickup_at_text,
          b.customer_user_id,
          st.code AS service_type_code,
          btd.id AS transfer_id,
          btd.flight_number,
          btd.airline_code,
          btd.flight_date,
          btd.departure_airport_iata,
          btd.arrival_airport_iata,
          btd.flight_scheduled_arrival_at,
          DATE_FORMAT(btd.flight_scheduled_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_scheduled_arrival_at_text,
          btd.flight_estimated_arrival_at,
          DATE_FORMAT(btd.flight_estimated_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_estimated_arrival_at_text,
          btd.flight_actual_arrival_at,
          DATE_FORMAT(btd.flight_actual_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_actual_arrival_at_text,
          btd.delay_minutes,
          btd.delay_status,
          btd.flight_status,
          btd.last_synced_at,
          DATE_FORMAT(btd.last_synced_at, '%Y-%m-%d %H:%i:%s') AS last_synced_at_text,
          btd.sync_status,
          btd.sync_error
        FROM bookings b
        INNER JOIN booking_transfer_details btd ON btd.booking_id = b.id
        INNER JOIN service_types st ON st.id = b.service_type_id
        WHERE b.id = ?
          AND b.deleted_at IS NULL
          AND btd.deleted_at IS NULL
          AND st.deleted_at IS NULL
        LIMIT 1
      `,
      [bookingId],
    );
    return rows[0] ?? null;
  }

  async updateFlightSync(conn, bookingId, data) {
    await conn.query(
      `
        UPDATE booking_transfer_details
        SET
          airline_code = ?,
          flight_date = ?,
          departure_airport_iata = ?,
          arrival_airport_iata = ?,
          flight_scheduled_arrival_at = ?,
          flight_estimated_arrival_at = ?,
          flight_actual_arrival_at = ?,
          delay_minutes = ?,
          delay_status = ?,
          flight_status = ?,
          last_synced_at = ?,
          sync_status = ?,
          sync_error = ?,
          updated_at = CURRENT_TIMESTAMP
        WHERE booking_id = ?
          AND deleted_at IS NULL
      `,
      [
        data.airlineCode,
        data.flightDate,
        data.departureAirportIata,
        data.arrivalAirportIata,
        data.flightScheduledArrivalAt,
        data.flightEstimatedArrivalAt,
        data.flightActualArrivalAt,
        data.delayMinutes,
        data.delayStatus,
        data.flightStatus,
        data.lastSyncedAt,
        data.syncStatus,
        data.syncError,
        bookingId,
      ],
    );
  }

  async listAutoSyncCandidates({ windowStart, windowEnd, limit }) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id AS booking_id,
          b.booking_number,
          b.status AS booking_status,
          b.scheduled_pickup_at,
          DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d %H:%i:%s') AS scheduled_pickup_at_text,
          st.code AS service_type_code,
          btd.id AS transfer_id,
          btd.flight_number,
          btd.airline_code,
          btd.flight_date,
          btd.departure_airport_iata,
          btd.arrival_airport_iata,
          btd.flight_scheduled_arrival_at,
          DATE_FORMAT(btd.flight_scheduled_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_scheduled_arrival_at_text,
          btd.flight_estimated_arrival_at,
          DATE_FORMAT(btd.flight_estimated_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_estimated_arrival_at_text,
          btd.flight_actual_arrival_at,
          DATE_FORMAT(btd.flight_actual_arrival_at, '%Y-%m-%d %H:%i:%s') AS flight_actual_arrival_at_text,
          btd.delay_minutes,
          btd.delay_status,
          btd.flight_status,
          btd.last_synced_at,
          DATE_FORMAT(btd.last_synced_at, '%Y-%m-%d %H:%i:%s') AS last_synced_at_text,
          btd.sync_status,
          btd.sync_error
        FROM bookings b
        INNER JOIN booking_transfer_details btd ON btd.booking_id = b.id
        INNER JOIN service_types st ON st.id = b.service_type_id
        WHERE b.deleted_at IS NULL
          AND btd.deleted_at IS NULL
          AND st.deleted_at IS NULL
          AND st.code = ?
          AND b.status NOT IN ('COMPLETED', 'CANCELLED', 'NO_SHOW')
          AND btd.flight_number IS NOT NULL
          AND TRIM(btd.flight_number) <> ''
          AND COALESCE(
            btd.flight_estimated_arrival_at,
            btd.flight_scheduled_arrival_at,
            b.scheduled_pickup_at
          ) >= ?
          AND COALESCE(
            btd.flight_estimated_arrival_at,
            btd.flight_scheduled_arrival_at,
            b.scheduled_pickup_at
          ) <= ?
        ORDER BY
          ABS(TIMESTAMPDIFF(
            MINUTE,
            COALESCE(btd.flight_estimated_arrival_at, btd.flight_scheduled_arrival_at, b.scheduled_pickup_at),
            CURRENT_TIMESTAMP
          )) ASC,
          CASE WHEN btd.flight_status IN ('DELAYED', 'ACTIVE') THEN 0 ELSE 1 END ASC,
          CASE WHEN btd.last_synced_at IS NULL THEN 0 ELSE 1 END ASC,
          btd.last_synced_at ASC,
          b.id ASC
        LIMIT ?
      `,
      [SERVICE_TYPES.AIRPORT_PICKUP, windowStart, windowEnd, limit],
    );
    return rows;
  }
}

module.exports = FlightMonitorRepository;
