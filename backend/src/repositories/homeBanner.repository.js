const database = require('../config/database');

class HomeBannerRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async getMaxDisplayOrder() {
    const [rows] = await this.pool.query(
      'SELECT COALESCE(MAX(display_order), -1) AS max_order FROM home_banners',
    );
    return Number(rows[0]?.max_order ?? -1);
  }

  async insertBanner({ imagePath, displayOrder, createdByAdminId = null }) {
    const [result] = await this.pool.query(
      `
        INSERT INTO home_banners (
          image_path,
          display_order,
          is_active,
          created_by_admin_id
        ) VALUES (?, ?, 1, ?)
      `,
      [imagePath, displayOrder, createdByAdminId],
    );
    return result.insertId;
  }

  async findById(bannerId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          image_path,
          display_order,
          is_active,
          created_by_admin_id,
          created_at,
          updated_at
        FROM home_banners
        WHERE id = ?
        LIMIT 1
      `,
      [bannerId],
    );
    return rows[0] || null;
  }

  async listAll() {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          image_path,
          display_order,
          is_active,
          created_by_admin_id,
          created_at,
          updated_at
        FROM home_banners
        ORDER BY display_order ASC, id ASC
      `,
    );
    return rows;
  }

  async listActive() {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          image_path,
          display_order,
          is_active,
          created_at,
          updated_at
        FROM home_banners
        WHERE is_active = 1
        ORDER BY display_order ASC, id ASC
      `,
    );
    return rows;
  }

  async updateBanner(bannerId, { isActive, displayOrder }) {
    const fields = [];
    const params = [];
    if (isActive != null) {
      fields.push('is_active = ?');
      params.push(isActive ? 1 : 0);
    }
    if (displayOrder != null) {
      fields.push('display_order = ?');
      params.push(displayOrder);
    }
    if (fields.length === 0) return 0;
    fields.push('updated_at = CURRENT_TIMESTAMP');
    params.push(bannerId);
    const [result] = await this.pool.query(
      `UPDATE home_banners SET ${fields.join(', ')} WHERE id = ?`,
      params,
    );
    return result.affectedRows;
  }

  async deleteById(bannerId) {
    const [result] = await this.pool.query(
      'DELETE FROM home_banners WHERE id = ?',
      [bannerId],
    );
    return result.affectedRows;
  }
}

module.exports = HomeBannerRepository;
