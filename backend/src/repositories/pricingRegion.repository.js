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
  async listFares() {
    const [rows] = await this.pool.query('SELECT id,origin_code origin,destination_code destination,vehicle_code vehicleTypeCode,price,currency FROM pricing_region_fares WHERE is_active=1 ORDER BY origin_code,destination_code,vehicle_code');
    return rows.map(r => ({ ...r, price: Number(r.price), regional: true }));
  }
  async findFare(origin, destination, vehicle) {
    const [rows] = await this.pool.query('SELECT id,price,currency FROM pricing_region_fares WHERE origin_code=? AND destination_code=? AND vehicle_code=? AND is_active=1', [origin,destination,vehicle]);
    return rows[0] ? { ...rows[0], price: Number(rows[0].price) } : null;
  }
  async updateFare(id, price) {
    const [result] = await this.pool.query('UPDATE pricing_region_fares SET price=? WHERE id=? AND is_active=1', [price,id]);
    return result.affectedRows > 0;
  }
}
module.exports = PricingRegionRepository;
