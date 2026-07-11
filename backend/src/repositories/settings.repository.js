const database = require('../config/database');

class SettingsRepository {
  constructor(pool = database.pool) {
    this.pool = pool;
  }

  async findByGroupAndKey(groupName, keyName, conn = null) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `
        SELECT value, data_type
        FROM settings
        WHERE group_name = ? AND key_name = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [groupName, keyName],
    );
    return rows[0] || null;
  }

  async findByGroup(groupName, conn = null) {
    const executor = conn ?? this.pool;
    const [rows] = await executor.query(
      `SELECT key_name, value, data_type FROM settings
       WHERE group_name = ? AND deleted_at IS NULL`,
      [groupName],
    );
    return rows;
  }

  async upsert(groupName, keyName, value, userId, conn = null) {
    const executor = conn ?? this.pool;
    await executor.query(
      `INSERT INTO settings
         (group_name, key_name, value, data_type, updated_by_user_id, created_by, updated_by)
       VALUES (?, ?, ?, 'STRING', ?, ?, ?)
       ON DUPLICATE KEY UPDATE value = VALUES(value),
         updated_by_user_id = VALUES(updated_by_user_id),
         updated_by = VALUES(updated_by), deleted_at = NULL`,
      [groupName, keyName, value, userId, userId, userId],
    );
  }
}

module.exports = SettingsRepository;
