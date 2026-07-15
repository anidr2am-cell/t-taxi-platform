const database = require('../config/database');

class DriverLocationRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findDriverByUserIdForUpdate(conn, userId) {
    const [rows] = await conn.query(
      `
        SELECT id, user_id, name, status, is_online, is_active
        FROM drivers
        WHERE user_id = ? AND deleted_at IS NULL AND is_archived = 0
        LIMIT 1
        FOR UPDATE
      `,
      [userId],
    );
    return rows[0] || null;
  }

  async hasActiveJob(conn, driverId) {
    const [rows] = await conn.query(
      `
        SELECT 1
        FROM booking_driver_assignments bda
        INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
        WHERE bda.driver_id = ?
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
          AND b.status IN ('DRIVER_ASSIGNED', 'DRIVER_ARRIVED', 'PICKED_UP')
        LIMIT 1
      `,
      [driverId],
    );
    return rows.length > 0;
  }

  async updateCurrentLocation(conn, driverId, location) {
    await conn.query(
      `
        UPDATE drivers
        SET
          current_lat = ?,
          current_lng = ?,
          current_accuracy_meters = ?,
          current_heading = ?,
          current_speed_kph = ?,
          location_recorded_at = ?,
          location_updated_at = CURRENT_TIMESTAMP,
          last_seen_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
      `,
      [
        location.latitude,
        location.longitude,
        location.accuracyMeters,
        location.heading,
        location.speedKph,
        location.recordedAtSql,
        driverId,
      ],
    );
  }

  async listAdminDriverLocations(filters = {}) {
    const where = [
      'd.deleted_at IS NULL',
      'd.is_archived = 0',
      'd.is_active = 1',
      'd.current_lat IS NOT NULL',
      'd.current_lng IS NOT NULL',
    ];
    const params = [];
    if (filters.onlineOnly) where.push('d.is_online = 1');
    if (filters.activeJobOnly) where.push('b.id IS NOT NULL');

    const [rows] = await this.pool.query(
      `
        SELECT
          d.id AS driver_id,
          d.name AS driver_name,
          d.status AS driver_status,
          d.is_online,
          d.current_lat,
          d.current_lng,
          d.current_accuracy_meters,
          d.current_heading,
          d.current_speed_kph,
          d.location_recorded_at,
          d.location_updated_at,
          d.last_seen_at,
          vt.name AS vehicle_type_name,
          dv.plate_number AS vehicle_plate,
          dv.model_name AS vehicle_model,
          b.booking_number,
          b.status AS booking_status
        FROM drivers d
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        LEFT JOIN vehicle_types vt ON vt.id = COALESCE(dv.vehicle_type_id, d.primary_vehicle_type_id)
          AND vt.deleted_at IS NULL
        LEFT JOIN booking_driver_assignments bda ON bda.driver_id = d.id
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
        LEFT JOIN bookings b ON b.id = bda.booking_id
          AND b.deleted_at IS NULL
          AND b.status IN ('DRIVER_ASSIGNED', 'DRIVER_ARRIVED', 'PICKED_UP')
        WHERE ${where.join(' AND ')}
        ORDER BY d.location_updated_at DESC, d.id ASC
      `,
      params,
    );
    return rows;
  }

  async findGuestAssignedDriverLocation(bookingId, tokenHash) {
    const [rows] = await this.pool.query(
      `
        SELECT
          b.id AS booking_id,
          b.booking_number,
          b.status AS booking_status,
          d.id AS driver_id,
          d.name AS driver_name,
          d.current_lat,
          d.current_lng,
          d.current_accuracy_meters,
          d.current_heading,
          d.current_speed_kph,
          d.location_recorded_at,
          d.location_updated_at,
          d.last_seen_at,
          vt.name AS vehicle_type_name,
          dv.plate_number AS vehicle_plate,
          dv.model_name AS vehicle_model
        FROM bookings b
        INNER JOIN guest_access_tokens gat ON gat.booking_id = b.id
          AND gat.token_hash = ?
          AND gat.revoked_at IS NULL
          AND gat.expires_at > CURRENT_TIMESTAMP
        LEFT JOIN booking_driver_assignments bda ON bda.booking_id = b.id
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
        LEFT JOIN drivers d ON d.id = bda.driver_id
          AND d.deleted_at IS NULL
          AND d.is_active = 1
          AND d.is_archived = 0
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        LEFT JOIN vehicle_types vt ON vt.id = COALESCE(dv.vehicle_type_id, d.primary_vehicle_type_id)
          AND vt.deleted_at IS NULL
        WHERE b.id = ? AND b.deleted_at IS NULL
        LIMIT 1
      `,
      [tokenHash, bookingId],
    );
    return rows[0] || null;
  }

  async listActiveBookingRoomsForDriver(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT b.id AS booking_id
        FROM booking_driver_assignments bda
        INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL AND b.is_archived = 0
        WHERE bda.driver_id = ?
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
          AND bda.status IN ('ASSIGNED', 'ACCEPTED')
          AND b.status IN ('DRIVER_ASSIGNED', 'DRIVER_ARRIVED', 'PICKED_UP')
      `,
      [driverId],
    );
    return rows.map((row) => Number(row.booking_id));
  }
}

module.exports = DriverLocationRepository;
