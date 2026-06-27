const database = require('../config/database');

class DriverRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async listForAdminAssignment() {
    const [rows] = await this.pool.query(
      `
        SELECT
          d.id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active,
          d.primary_vehicle_type_id,
          vt.code AS primary_vehicle_type_code,
          vt.name AS primary_vehicle_type_name,
          dv.id AS primary_vehicle_id,
          dv.plate_number AS primary_vehicle_plate,
          dv.model_name AS primary_vehicle_model,
          (
            SELECT COUNT(*)
            FROM booking_driver_assignments bda
            INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
            WHERE bda.driver_id = d.id
              AND bda.is_active = 1
              AND bda.deleted_at IS NULL
              AND bda.status IN ('ASSIGNED', 'ACCEPTED')
              AND b.status NOT IN ('COMPLETED', 'CANCELLED', 'NO_SHOW')
          ) AS active_assignment_count,
          (
            SELECT ROUND(AVG(r.rating), 1)
            FROM reviews r
            WHERE r.driver_id = d.id
              AND r.moderation_status = 'VISIBLE'
          ) AS average_rating,
          (
            SELECT COUNT(*)
            FROM reviews r
            WHERE r.driver_id = d.id
              AND r.moderation_status = 'VISIBLE'
          ) AS review_count
        FROM drivers d
        LEFT JOIN vehicle_types vt ON vt.id = d.primary_vehicle_type_id AND vt.deleted_at IS NULL
        LEFT JOIN driver_vehicles dv ON dv.driver_id = d.id
          AND dv.is_primary = 1
          AND dv.is_active = 1
          AND dv.deleted_at IS NULL
        WHERE d.deleted_at IS NULL
        ORDER BY d.name ASC
      `,
    );
    return rows;
  }

  async findByIdForUpdate(conn, driverId) {
    const [rows] = await conn.query(
      `
        SELECT
          d.id,
          d.user_id,
          d.name,
          d.phone,
          d.status,
          d.is_online,
          d.is_active
        FROM drivers d
        WHERE d.id = ? AND d.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
      `,
      [driverId],
    );
    return rows[0] || null;
  }

  async findPrimaryVehicle(conn, driverId) {
    const [rows] = await conn.query(
      `
        SELECT id, vehicle_type_id, plate_number, model_name
        FROM driver_vehicles
        WHERE driver_id = ?
          AND is_primary = 1
          AND is_active = 1
          AND deleted_at IS NULL
        LIMIT 1
      `,
      [driverId],
    );
    return rows[0] || null;
  }

  async findById(driverId) {
    const [rows] = await this.pool.query(
      `
        SELECT id, user_id, name, phone, status, is_online, is_active
        FROM drivers
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [driverId],
    );
    return rows[0] || null;
  }

  async findByUserId(userId) {
    const [rows] = await this.pool.query(
      `
        SELECT id, user_id, name, phone, status, is_online, is_active
        FROM drivers
        WHERE user_id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [userId],
    );
    return rows[0] || null;
  }
}

module.exports = DriverRepository;
