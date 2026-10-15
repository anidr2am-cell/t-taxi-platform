const database = require('../config/database');
class PricingRegionRepository {
  constructor(pool = database.pool) { this.pool = pool; }
  async list() {
    const [rows] = await this.pool.query('SELECT id,code,fare_location_code,airport_iata,geometry,priority,is_active FROM pricing_regions ORDER BY priority DESC,code');
    return rows.map(r => ({ ...r, geometry: typeof r.geometry === 'string' ? JSON.parse(r.geometry) : r.geometry }));
  }
  async update(id, body) {
    const [result] = await this.pool.query('UPDATE pricing_regions SET geometry=?,priority=?,is_active=? WHERE id=?',
      [JSON.stringify(body.geometry), body.priority, body.isActive, id]);
    return result.affectedRows > 0;
  }
}
module.exports = PricingRegionRepository;
