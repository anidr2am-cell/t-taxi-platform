const database = require('../config/database');

class CityTransferDistanceBandRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  mapRow(row) {
    if (!row) {
      return null;
    }

    return {
      id: row.id,
      minKm: Number(row.min_km),
      maxKm: row.max_km == null ? null : Number(row.max_km),
      sedanPrice: row.sedan_price == null ? null : Number(row.sedan_price),
      suvPrice: row.suv_price == null ? null : Number(row.suv_price),
      vanPrice: row.van_price == null ? null : Number(row.van_price),
      currency: row.currency,
      isActive: Boolean(row.is_active),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  async findAll({ includeInactive = false } = {}) {
    const where = ['1 = 1'];
    if (!includeInactive) {
      where.push('is_active = 1');
    }

    const [rows] = await this.pool.query(
      `
        SELECT
          id, min_km, max_km,
          sedan_price, suv_price, van_price,
          currency, is_active, created_at, updated_at
        FROM city_transfer_distance_bands
        WHERE ${where.join(' AND ')}
        ORDER BY min_km ASC, id ASC
      `,
    );
    return rows.map((row) => this.mapRow(row));
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id, min_km, max_km,
          sedan_price, suv_price, van_price,
          currency, is_active, created_at, updated_at
        FROM city_transfer_distance_bands
        WHERE id = ?
        LIMIT 1
      `,
      [id],
    );
    return this.mapRow(rows[0]);
  }

  async findActiveBandByDistance(distanceKm) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id, min_km, max_km,
          sedan_price, suv_price, van_price,
          currency, is_active, created_at, updated_at
        FROM city_transfer_distance_bands
        WHERE is_active = 1
          AND min_km <= ?
          AND (max_km IS NULL OR max_km >= ?)
        ORDER BY min_km DESC, id DESC
        LIMIT 1
      `,
      [distanceKm, distanceKm],
    );
    return this.mapRow(rows[0]);
  }

  async update(id, data) {
    const fields = [];
    const values = [];

    if (data.sedanPrice !== undefined) {
      fields.push('sedan_price = ?');
      values.push(data.sedanPrice);
    }
    if (data.suvPrice !== undefined) {
      fields.push('suv_price = ?');
      values.push(data.suvPrice);
    }
    if (data.vanPrice !== undefined) {
      fields.push('van_price = ?');
      values.push(data.vanPrice);
    }
    if (data.isActive !== undefined) {
      fields.push('is_active = ?');
      values.push(data.isActive ? 1 : 0);
    }

    if (!fields.length) {
      return this.findById(id);
    }

    values.push(id);
    await this.pool.query(
      `
        UPDATE city_transfer_distance_bands
        SET ${fields.join(', ')}, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `,
      values,
    );
    return this.findById(id);
  }
}

module.exports = CityTransferDistanceBandRepository;
