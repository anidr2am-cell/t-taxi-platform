const database = require('../config/database');
class GolfPricingRepository {
  constructor(pool = database.pool) { this.pool = pool; }
  async listCourses(region = null) {
    const [rows] = await this.pool.query(`SELECT g.id,g.name,g.region,g.lat,g.lng,c.code,c.names,c.fare_group fareGroup,c.coordinate_source coordinateSource
      FROM golf_courses g JOIN golf_course_catalog c ON c.golf_course_id=g.id
      WHERE g.is_active=1 AND g.deleted_at IS NULL ${region ? 'AND g.region=?' : ''} ORDER BY c.fare_group,g.name`, region ? [region] : []);
    return rows.map(r => ({ ...r, lat:Number(r.lat),lng:Number(r.lng), names:typeof r.names==='string'?JSON.parse(r.names):r.names }));
  }
  async findCourse(id) { return (await this.listCourses()).find(c => c.id===Number(id)) ?? null; }
  async listPrices() {
    const [rows] = await this.pool.query('SELECT id,fare_group fareGroup,vehicle_code vehicleTypeCode,holes,round_trip_price roundTripPrice FROM golf_group_prices WHERE is_active=1 ORDER BY fare_group,vehicle_code,holes');
    return rows.map(r=>({...r,roundTripPrice:Number(r.roundTripPrice)}));
  }
  async findPrice(group,vehicle,holes) {
    const [rows] = await this.pool.query('SELECT id,round_trip_price price FROM golf_group_prices WHERE fare_group=? AND vehicle_code=? AND holes=? AND is_active=1',[group,vehicle,holes]);
    return rows[0] ? {...rows[0],price:Number(rows[0].price)} : null;
  }
  async updatePrice(id,price,userId) {
    const conn=await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const [rows]=await conn.query('SELECT round_trip_price FROM golf_group_prices WHERE id=? AND is_active=1 FOR UPDATE',[id]);
      if (!rows[0]) { await conn.rollback(); return false; }
      await conn.query('UPDATE golf_group_prices SET round_trip_price=? WHERE id=?',[price,id]);
      await conn.query('INSERT INTO audit_logs(user_id,action,entity_type,entity_id,payload) VALUES(?,?,?,?,?)',
        [userId,'GOLF_GROUP_PRICE_UPDATED','golf_group_prices',id,JSON.stringify({before:Number(rows[0].round_trip_price),after:price})]);
      await conn.commit(); return true;
    } catch(e) { await conn.rollback(); throw e; } finally { conn.release(); }
  }
}
module.exports=GolfPricingRepository;
