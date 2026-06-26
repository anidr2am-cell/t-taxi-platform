const database = require('../config/database');

class LocationRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findByCode(code) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id, code, type, display_name, google_place_id,
          airport_id, golf_course_id, latitude, longitude, is_active
        FROM locations
        WHERE code = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [code],
    );
    return rows[0] || null;
  }

  async findByAirportIata(iataCode) {
    const [rows] = await this.pool.query(
      `
        SELECT
          l.id, l.code, l.type, l.display_name, l.google_place_id,
          l.airport_id, l.golf_course_id, l.latitude, l.longitude, l.is_active
        FROM locations l
        INNER JOIN airports a ON a.id = l.airport_id
        WHERE a.iata_code = ?
          AND l.deleted_at IS NULL
          AND a.deleted_at IS NULL
        LIMIT 1
      `,
      [iataCode],
    );
    return rows[0] || null;
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id, code, type, display_name, google_place_id,
          airport_id, golf_course_id, latitude, longitude, is_active
        FROM locations
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [id],
    );
    return rows[0] || null;
  }
}

module.exports = LocationRepository;
