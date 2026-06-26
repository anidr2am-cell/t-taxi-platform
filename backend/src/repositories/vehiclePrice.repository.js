const database = require('../config/database');

class VehiclePriceRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  mapRow(row) {
    if (!row) {
      return null;
    }

    return {
      id: row.id,
      routeId: row.route_id,
      vehicleTypeId: row.vehicle_type_id,
      vehicleTypeCode: row.vehicle_type_code,
      price: Number(row.price),
      currency: row.currency,
      isActive: Boolean(row.is_active),
      effectiveFrom: row.effective_from,
      effectiveTo: row.effective_to,
      createdBy: row.created_by,
      updatedBy: row.updated_by,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  baseSelect() {
    return `
      SELECT
        vp.id,
        vp.route_id,
        vp.vehicle_type_id,
        vt.code AS vehicle_type_code,
        vp.price,
        vp.currency,
        vp.is_active,
        vp.effective_from,
        vp.effective_to,
        vp.created_by,
        vp.updated_by,
        vp.created_at,
        vp.updated_at
      FROM vehicle_prices vp
      INNER JOIN vehicle_types vt ON vt.id = vp.vehicle_type_id
    `;
  }

  async findAll({ routeId, includeInactive = false } = {}) {
    const where = ['vp.deleted_at IS NULL'];
    const values = [];

    if (routeId) {
      where.push('vp.route_id = ?');
      values.push(routeId);
    }
    if (!includeInactive) {
      where.push('vp.is_active = 1');
    }

    const [rows] = await this.pool.query(
      `${this.baseSelect()}
       WHERE ${where.join(' AND ')}
       ORDER BY vt.sort_order ASC, vp.id ASC`,
      values,
    );
    return rows.map((row) => this.mapRow(row));
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `${this.baseSelect()}
       WHERE vp.id = ? AND vp.deleted_at IS NULL
       LIMIT 1`,
      [id],
    );
    return this.mapRow(rows[0]);
  }

  async findActiveByRouteAndVehicleType(routeId, vehicleTypeId, { excludeId } = {}) {
    const where = [
      'vp.route_id = ?',
      'vp.vehicle_type_id = ?',
      'vp.is_active = 1',
      'vp.deleted_at IS NULL',
    ];
    const values = [routeId, vehicleTypeId];

    if (excludeId) {
      where.push('vp.id <> ?');
      values.push(excludeId);
    }

    const [rows] = await this.pool.query(
      `${this.baseSelect()}
       WHERE ${where.join(' AND ')}
       ORDER BY vp.id ASC`,
      values,
    );
    return rows.map((row) => this.mapRow(row));
  }

  async findByRouteId(routeId, { includeInactive = true } = {}) {
    return this.findAll({ routeId, includeInactive });
  }

  async create(data) {
    const [result] = await this.pool.query(
      `
        INSERT INTO vehicle_prices (
          route_id, vehicle_type_id, price, currency,
          is_active, effective_from, effective_to,
          created_by, updated_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        data.routeId,
        data.vehicleTypeId,
        data.price,
        data.currency ?? 'THB',
        data.isActive ?? 1,
        data.effectiveFrom ?? null,
        data.effectiveTo ?? null,
        data.createdBy ?? null,
        data.updatedBy ?? null,
      ],
    );
    return this.findById(result.insertId);
  }

  async update(id, data) {
    const fields = [];
    const values = [];

    if (data.price !== undefined) {
      fields.push('price = ?');
      values.push(data.price);
    }
    if (data.currency !== undefined) {
      fields.push('currency = ?');
      values.push(data.currency);
    }
    if (data.isActive !== undefined) {
      fields.push('is_active = ?');
      values.push(data.isActive ? 1 : 0);
    }
    if (data.effectiveFrom !== undefined) {
      fields.push('effective_from = ?');
      values.push(data.effectiveFrom);
    }
    if (data.effectiveTo !== undefined) {
      fields.push('effective_to = ?');
      values.push(data.effectiveTo);
    }
    if (data.updatedBy !== undefined) {
      fields.push('updated_by = ?');
      values.push(data.updatedBy);
    }

    if (fields.length === 0) {
      return this.findById(id);
    }

    values.push(id);
    await this.pool.query(
      `UPDATE vehicle_prices SET ${fields.join(', ')} WHERE id = ? AND deleted_at IS NULL`,
      values,
    );
    return this.findById(id);
  }

  async softDelete(id, updatedBy) {
    await this.pool.query(
      `
        UPDATE vehicle_prices
        SET deleted_at = CURRENT_TIMESTAMP, updated_by = ?, is_active = 0
        WHERE id = ? AND deleted_at IS NULL
      `,
      [updatedBy ?? null, id],
    );
    return true;
  }

  /**
   * Bulk insert vehicle prices — reserved for future CSV import pipelines.
   */
  async bulkCreate(rows) {
    if (!rows.length) {
      return [];
    }

    const placeholders = rows.map(() => '(?, ?, ?, ?, ?, ?, ?, ?, ?)').join(', ');
    const values = rows.flatMap((row) => [
      row.routeId,
      row.vehicleTypeId,
      row.price,
      row.currency ?? 'THB',
      row.isActive ?? 1,
      row.effectiveFrom ?? null,
      row.effectiveTo ?? null,
      row.createdBy ?? null,
      row.updatedBy ?? null,
    ]);

    const [result] = await this.pool.query(
      `
        INSERT INTO vehicle_prices (
          route_id, vehicle_type_id, price, currency,
          is_active, effective_from, effective_to,
          created_by, updated_by
        ) VALUES ${placeholders}
      `,
      values,
    );

    const ids = Array.from({ length: rows.length }, (_, i) => result.insertId + i);
    const created = [];
    for (const id of ids) {
      created.push(await this.findById(id));
    }
    return created;
  }
}

module.exports = VehiclePriceRepository;
