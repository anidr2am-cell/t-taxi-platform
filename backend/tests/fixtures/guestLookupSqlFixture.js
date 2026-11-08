// Deliberately minimal QA schema for the unmodified guest lookup SELECT/joins.
// Never use an application/production database for this fixture.
async function prepareGuestLookupFixture(pool) {
  const [[{ name }]] = await pool.query('SELECT DATABASE() AS name');
  if (!/^qa_guest_lookup_[a-z0-9_]+$/.test(name ?? '')) {
    throw new Error('Guest lookup fixture requires its own qa_guest_lookup_* database');
  }
  const ddl = [
    `CREATE TABLE IF NOT EXISTS bookings (
      id INT PRIMARY KEY, booking_number VARCHAR(30), customer_name VARCHAR(100),
      status VARCHAR(30), customer_phone VARCHAR(30), customer_phone_digits VARCHAR(30),
      customer_country_code VARCHAR(10), customer_user_id INT, service_type_id INT,
      vehicle_type_id INT, driver_id INT, scheduled_pickup_at DATETIME,
      origin_address VARCHAR(100), destination_address VARCHAR(100),
      origin_lat DECIMAL(10,7), origin_lng DECIMAL(10,7),
      destination_lat DECIMAL(10,7), destination_lng DECIMAL(10,7), metadata JSON,
      payment_method VARCHAR(30), payment_status VARCHAR(30), total_amount DECIMAL(10,2),
      currency VARCHAR(5), vehicle_count INT, route_id INT,
      boarding_qr_token_hash VARCHAR(64), boarding_qr_used_at DATETIME,
      dropoff_qr_token_hash VARCHAR(64), dropoff_qr_used_at DATETIME,
      prefer_female_driver TINYINT DEFAULT 0, is_archived TINYINT DEFAULT 0, deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS service_types(id INT PRIMARY KEY,code VARCHAR(30),name VARCHAR(50),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS vehicle_types(id INT PRIMARY KEY,code VARCHAR(30),name VARCHAR(50),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS routes(id INT PRIMARY KEY,origin_location_id INT,destination_location_id INT,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS locations(id INT PRIMARY KEY,code VARCHAR(30),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS booking_passengers(booking_id INT,adults INT,children INT,infants INT,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS booking_luggage(booking_id INT,carriers_20_inch INT,carriers_24_inch_plus INT,golf_bags INT,special_items TEXT,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS booking_transfer_details(booking_id INT,flight_number VARCHAR(20),airport_code_custom VARCHAR(10),airport_id INT,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS airports(id INT PRIMARY KEY,iata_code VARCHAR(5),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS booking_driver_assignments(id INT PRIMARY KEY,booking_id INT,driver_id INT,driver_vehicle_id INT,is_active TINYINT,assignment_reason VARCHAR(80),updated_at DATETIME,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS drivers(id INT PRIMARY KEY,user_id INT,name VARCHAR(80),phone VARCHAR(30),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS driver_vehicles(id INT PRIMARY KEY,plate_number VARCHAR(30),model_name VARCHAR(50),color VARCHAR(30),vehicle_type_id INT,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS booking_charge_items(booking_id INT,charge_type VARCHAR(30),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS files(id INT PRIMARY KEY,entity_type VARCHAR(40),entity_id INT,deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS driver_applications(id INT PRIMARY KEY,approved_driver_id INT,status VARCHAR(30),deleted_at DATETIME)`,
    `CREATE TABLE IF NOT EXISTS driver_application_files(driver_application_id INT,category VARCHAR(40),file_id INT,sort_order INT)`,
    `CREATE TABLE IF NOT EXISTS guest_access_tokens(id INT AUTO_INCREMENT PRIMARY KEY,booking_id INT,token_hash VARCHAR(64),expires_at DATETIME)`,
  ];
  for (const sql of ddl) await pool.query(sql);
  await pool.query("INSERT IGNORE INTO service_types VALUES(1,'AIRPORT_PICKUP','Airport pickup',NULL)");
  await pool.query("INSERT IGNORE INTO vehicle_types VALUES(1,'SEDAN','Sedan',NULL)");
  await pool.query("INSERT IGNORE INTO drivers VALUES(2,20,'QA Driver',NULL,NULL)");
  for (let id = 1; id <= 5; id++) {
    await pool.query(`INSERT INTO bookings
      (id,booking_number,customer_name,status,customer_phone,customer_phone_digits,
       customer_country_code,customer_user_id,service_type_id,vehicle_type_id,driver_id,
       scheduled_pickup_at,origin_address,destination_address,metadata,payment_method,
       payment_status,total_amount,currency,vehicle_count,is_archived,deleted_at)
      VALUES(?,?,?,'DRIVER_ASSIGNED',?,?,'TH',42,1,1,2,'2099-01-01 09:30:00',
       'QA airport','QA hotel','{}','PAY_DRIVER','UNPAID',1000,'THB',1,?,?)
      ON DUPLICATE KEY UPDATE customer_name=VALUES(customer_name),is_archived=VALUES(is_archived),deleted_at=VALUES(deleted_at)`,
    [id, `TX20990101${String(id).padStart(4, '0')}`,
      id === 5 ? 'ทดสอบ ลูกค้า' : 'QA Guest Example',
      id === 4 ? null : '+66812345678', id === 4 ? null : '66812345678',
      id === 2 ? 1 : 0, id === 3 ? '2098-01-01 00:00:00' : null]);
  }
  await pool.query('DELETE FROM guest_access_tokens WHERE booking_id BETWEEN 1 AND 5');
}

module.exports = { prepareGuestLookupFixture };
