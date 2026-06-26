const database = require('../config/database');

class RouteRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  mapRow(row) {
    if (!row) {
      return null;
    }

    return {
      id: row.id,
      serviceTypeId: row.service_type_id,
      serviceTypeCode: row.service_type_code,
      originLocationId: row.origin_location_id,
      originLocationCode: row.origin_location_code,
      originDisplayName: row.origin_display_name,
      destinationLocationId: row.destination_location_id,
      destinationLocationCode: row.destination_location_code,
      destinationDisplayName: row.destination_display_name,
      isActive: Boolean(row.is_active),
      displayOrder: row.display_order,
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
        r.id,
        r.service_type_id,
        st.code AS service_type_code,
        r.origin_location_id,
        lo.code AS origin_location_code,
        lo.display_name AS origin_display_name,
        r.destination_location_id,
        ld.code AS destination_location_code,
        ld.display_name AS destination_display_name,
        r.is_active,
        r.display_order,
        r.effective_from,
        r.effective_to,
        r.created_by,
        r.updated_by,
        r.created_at,
        r.updated_at
      FROM routes r
      INNER JOIN service_types st ON st.id = r.service_type_id
      INNER JOIN locations lo ON lo.id = r.origin_location_id
      INNER JOIN locations ld ON ld.id = r.destination_location_id
    `;
  }

  async findAll({ includeInactive = false } = {}) {
    const where = ['r.deleted_at IS NULL'];
    if (!includeInactive) {
      where.push('r.is_active = 1');
    }

    const [rows] = await this.pool.query(
      `${this.baseSelect()}
       WHERE ${where.join(' AND ')}
       ORDER BY r.display_order ASC, r.id ASC`,
    );
    return rows.map((row) => this.mapRow(row));
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `${this.baseSelect()}
       WHERE r.id = ? AND r.deleted_at IS NULL
       LIMIT 1`,
      [id],
    );
    return this.mapRow(rows[0]);
  }

  async findActiveByServiceAndLocations(serviceTypeId, originLocationId, destinationLocationId) {
    const [rows] = await this.pool.query(
      `${this.baseSelect()}
       WHERE r.service_type_id = ?
         AND r.origin_location_id = ?
         AND r.destination_location_id = ?
         AND r.is_active = 1
         AND r.deleted_at IS NULL
       ORDER BY r.display_order ASC, r.id ASC`,
      [serviceTypeId, originLocationId, destinationLocationId],
    );
    return rows.map((row) => this.mapRow(row));
  }

  async create(data) {
    const [result] = await this.pool.query(
      `
        INSERT INTO routes (
          service_type_id, origin_location_id, destination_location_id,
          is_active, display_order, effective_from, effective_to,
          created_by, updated_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        data.serviceTypeId,
        data.originLocationId,
        data.destinationLocationId,
        data.isActive ?? 1,
        data.displayOrder ?? 0,
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

    if (data.serviceTypeId !== undefined) {
      fields.push('service_type_id = ?');
      values.push(data.serviceTypeId);
    }
    if (data.originLocationId !== undefined) {
      fields.push('origin_location_id = ?');
      values.push(data.originLocationId);
    }
    if (data.destinationLocationId !== undefined) {
      fields.push('destination_location_id = ?');
      values.push(data.destinationLocationId);
    }
    if (data.isActive !== undefined) {
      fields.push('is_active = ?');
      values.push(data.isActive ? 1 : 0);
    }
    if (data.displayOrder !== undefined) {
      fields.push('display_order = ?');
      values.push(data.displayOrder);
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
      `UPDATE routes SET ${fields.join(', ')} WHERE id = ? AND deleted_at IS NULL`,
      values,
    );
    return this.findById(id);
  }

  async softDelete(id, updatedBy) {
    await this.pool.query(
      `
        UPDATE routes
        SET deleted_at = CURRENT_TIMESTAMP, updated_by = ?, is_active = 0
        WHERE id = ? AND deleted_at IS NULL
      `,
      [updatedBy ?? null, id],
    );
    return true;
  }

  /**
   * Bulk insert routes — reserved for future CSV import pipelines.
   */
  async bulkCreate(rows) {
    if (!rows.length) {
      return [];
    }

    const placeholders = rows.map(() => '(?, ?, ?, ?, ?, ?, ?, ?, ?)').join(', ');
    const values = rows.flatMap((row) => [
      row.serviceTypeId,
      row.originLocationId,
      row.destinationLocationId,
      row.isActive ?? 1,
      row.displayOrder ?? 0,
      row.effectiveFrom ?? null,
      row.effectiveTo ?? null,
      row.createdBy ?? null,
      row.updatedBy ?? null,
    ]);

    const [result] = await this.pool.query(
      `
        INSERT INTO routes (
          service_type_id, origin_location_id, destination_location_id,
          is_active, display_order, effective_from, effective_to,
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

module.exports = RouteRepository;
