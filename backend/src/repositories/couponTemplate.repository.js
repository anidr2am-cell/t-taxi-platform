const database = require('../config/database');

class CouponTemplateRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async insertTemplate({
    title,
    discountAmount,
    imagePath,
    createdByAdminId = null,
  }) {
    const [result] = await this.pool.query(
      `
        INSERT INTO coupon_templates (
          title,
          discount_amount,
          image_path,
          is_active,
          created_by_admin_id
        ) VALUES (?, ?, ?, 1, ?)
      `,
      [title, discountAmount, imagePath, createdByAdminId],
    );
    return result.insertId;
  }

  async findById(templateId) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          title,
          discount_amount,
          image_path,
          is_active,
          created_by_admin_id,
          created_at,
          updated_at
        FROM coupon_templates
        WHERE id = ?
        LIMIT 1
      `,
      [templateId],
    );
    return rows[0] || null;
  }

  async listAll() {
    const [rows] = await this.pool.query(
      `
        SELECT
          id,
          title,
          discount_amount,
          image_path,
          is_active,
          created_by_admin_id,
          created_at,
          updated_at
        FROM coupon_templates
        ORDER BY is_active DESC, id DESC
      `,
    );
    return rows;
  }

  async updateIsActive(templateId, isActive) {
    const [result] = await this.pool.query(
      `
        UPDATE coupon_templates
        SET is_active = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      [isActive ? 1 : 0, templateId],
    );
    return result.affectedRows;
  }
}

module.exports = CouponTemplateRepository;
