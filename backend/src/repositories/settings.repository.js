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
}

module.exports = SettingsRepository;
