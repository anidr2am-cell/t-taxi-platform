const database = require('../config/database');

class ServiceTypeRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findByCode(code) {
    const [rows] = await this.pool.query(
      `
        SELECT id, code, name, category_id, is_active
        FROM service_types
        WHERE code = ? AND deleted_at IS NULL AND is_active = 1
        LIMIT 1
      `,
      [code],
    );
    return rows[0] || null;
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT id, code, name, category_id, is_active
        FROM service_types
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [id],
    );
    return rows[0] || null;
  }
}

module.exports = ServiceTypeRepository;
