const database = require('../config/database');

class VehicleRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findActiveTypesOrdered() {
    const [rows] = await this.pool.query(
      `
        SELECT id, code, name, sort_order, max_passengers, max_luggage
        FROM vehicle_types
        WHERE is_active = 1 AND deleted_at IS NULL
        ORDER BY sort_order ASC
      `,
    );
    return rows;
  }

  async findPublicTypesOrdered() {
    const [rows] = await this.pool.query(
      `
        SELECT id, code, name, max_passengers, max_luggage, is_active
        FROM vehicle_types
        WHERE is_active = 1 AND deleted_at IS NULL
        ORDER BY id ASC
      `,
    );
    return rows;
  }

  async findTypeById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT id, code, name, sort_order, max_passengers, max_luggage
        FROM vehicle_types
        WHERE id = ? AND deleted_at IS NULL AND is_active = 1
        LIMIT 1
      `,
      [id],
    );
    return rows[0] || null;
  }

  async findTypeByCode(code) {
    const [rows] = await this.pool.query(
      `
        SELECT id, code, name, sort_order, max_passengers, max_luggage
        FROM vehicle_types
        WHERE code = ? AND deleted_at IS NULL AND is_active = 1
        LIMIT 1
      `,
      [code],
    );
    return rows[0] || null;
  }

  async findActiveCapacityRules() {
    const [rows] = await this.pool.query(
      `
        SELECT
          vt.code,
          vt.sort_order,
          vcr.max_passengers,
          vcr.max_carriers_20_inch,
          vcr.max_carriers_24_inch_plus,
          vcr.max_golf_bags,
          vcr.max_special_luggage,
          vcr.priority
        FROM vehicle_capacity_rules vcr
        INNER JOIN vehicle_types vt ON vt.id = vcr.vehicle_type_id
        WHERE vcr.is_active = 1
          AND vcr.deleted_at IS NULL
          AND vt.is_active = 1
          AND vt.deleted_at IS NULL
        ORDER BY vt.sort_order ASC
      `,
    );
    return rows;
  }
}

module.exports = VehicleRepository;
