const database = require('../config/database');

class ChargePolicyRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  mapRow(row) {
    if (!row) {
      return null;
    }

    return {
      id: row.id,
      chargeType: row.charge_type,
      calculationType: row.calculation_type,
      amount: Number(row.amount),
      isActive: Boolean(row.is_active),
      effectiveFrom: row.effective_from,
      effectiveTo: row.effective_to,
      createdBy: row.created_by,
      updatedBy: row.updated_by,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  async findAll({ includeInactive = false } = {}) {
    const where = ['deleted_at IS NULL'];
    if (!includeInactive) {
      where.push('is_active = 1');
    }

    const [rows] = await this.pool.query(
      `
        SELECT
          id, charge_type, calculation_type, amount,
          is_active, effective_from, effective_to,
          created_by, updated_by,
          created_at, updated_at
        FROM charge_policies
        WHERE ${where.join(' AND ')}
        ORDER BY charge_type ASC, id ASC
      `,
    );
    return rows.map((row) => this.mapRow(row));
  }

  async findById(id) {
    const [rows] = await this.pool.query(
      `
        SELECT
          id, charge_type, calculation_type, amount,
          is_active, effective_from, effective_to,
          created_by, updated_by,
          created_at, updated_at
        FROM charge_policies
        WHERE id = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [id],
    );
    return this.mapRow(rows[0]);
  }

  async findActivePolicies() {
    return this.findAll({ includeInactive: false });
  }

  async create(data) {
    const [result] = await this.pool.query(
      `
        INSERT INTO charge_policies (
          charge_type, calculation_type, amount,
          is_active, effective_from, effective_to,
          created_by, updated_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        data.chargeType,
        data.calculationType,
        data.amount,
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

    if (data.chargeType !== undefined) {
      fields.push('charge_type = ?');
      values.push(data.chargeType);
    }
    if (data.calculationType !== undefined) {
      fields.push('calculation_type = ?');
      values.push(data.calculationType);
    }
    if (data.amount !== undefined) {
      fields.push('amount = ?');
      values.push(data.amount);
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
      `UPDATE charge_policies SET ${fields.join(', ')} WHERE id = ? AND deleted_at IS NULL`,
      values,
    );
    return this.findById(id);
  }

  async softDelete(id, updatedBy) {
    await this.pool.query(
      `
        UPDATE charge_policies
        SET deleted_at = CURRENT_TIMESTAMP, updated_by = ?, is_active = 0
        WHERE id = ? AND deleted_at IS NULL
      `,
      [updatedBy ?? null, id],
    );
    return true;
  }
}

module.exports = ChargePolicyRepository;
