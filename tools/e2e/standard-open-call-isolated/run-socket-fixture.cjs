// Isolated drivers/bookings for socket QA (no overlap with boundary/UI seq).
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');

assert.equal(process.env.DB_HOST, 'tride-qa-admin-db');
assert.equal(process.env.DB_NAME, 'tride_qa_admin');

const requireBackend = createRequire(`${process.cwd()}/package.json`);
const jwt = requireBackend('jsonwebtoken');
const bcrypt = requireBackend('bcryptjs');
const { pool } = requireBackend('./src/config/database');
const { resolveQaDriverPassword } = require('./qa-driver-password.cjs');

const QA_API = (process.env.QA_API_BASE || 'http://127.0.0.1:3000/api/v1').replace(/\/$/, '');
const GATE = String(process.env.CONTACT_CONNECTION_REQUIRED || 'false').toLowerCase() === 'true';
const OUT = process.env.SOCKET_FIXTURE_PATH || '/srv/tride/backend/socket-fixture.json';

const SOCKET_DRIVER_USER_ID = Number(process.env.SOCKET_DRIVER_USER_ID || 11);

function sign(user) {
  return jwt.sign(
    { sub: user.id, role: user.role, email: user.email, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '45m' },
  );
}

async function api(method, path, { token, body, status = 200, headers = {} } = {}) {
  const h = { 'Content-Type': 'application/json', ...headers };
  if (token) h.Authorization = `Bearer ${token}`;
  const res = await fetch(`${QA_API}${path}`, {
    method,
    headers: h,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  assert.equal(res.status, status, JSON.stringify(json));
  return json.data ?? json;
}

async function seed() {
  const hash = await bcrypt.hash(resolveQaDriverPassword(), 10);
  const driverRows = [
    { id: 10, email: 'qa-oc-driver-a@example.invalid', phone: '1111111001' },
    { id: 11, email: 'qa-oc-driver-socket@example.invalid', phone: '1111111002' },
  ];
  const [[n]] = await pool.query('SELECT COUNT(*) c FROM users WHERE id=1');
  if (n.c === 0) {
    await pool.query(
      `INSERT INTO users(id,email,role,is_active,password_hash) VALUES
       (1,'qa-oc-admin@example.invalid','ADMIN',1,NULL),
       (2,'qa-oc-customer@example.invalid','CUSTOMER',1,NULL)`,
    );
    await pool.query(`
      INSERT INTO city_transfer_distance_bands
        (min_km, max_km, sedan_price, suv_price, van_price, currency, is_active)
      VALUES (0, 12, NULL, NULL, NULL, 'THB', 1),
             (13, 50, 900, 1100, 1400, 'THB', 1)`);
    await pool.query(
      `INSERT INTO settings(group_name,key_name,value,data_type) VALUES
       ('contact_channels','contactLineEnabled','true','boolean'),
       ('contact_channels','contactLineDisplayName','QA Line','string'),
       ('contact_channels','contactLineAddUrl','https://line.me/example','string')`,
    );
  }
  const [[sedan]] = await pool.query("SELECT id FROM vehicle_types WHERE code='SEDAN'");
  assert.ok(sedan, 'SEDAN vehicle type required');
  for (const row of driverRows) {
    await pool.query(
      `INSERT INTO users (id, email, role, is_active, password_hash, phone)
       VALUES (?, ?, 'DRIVER', 1, ?, ?)
       ON DUPLICATE KEY UPDATE
         email = VALUES(email),
         role = 'DRIVER',
         is_active = 1,
         password_hash = VALUES(password_hash),
         phone = VALUES(phone),
         deleted_at = NULL`,
      [row.id, row.email, hash, row.phone],
    );
    const [[existingDriver]] = await pool.query('SELECT id FROM drivers WHERE id = ?', [row.id]);
    if (!existingDriver) {
      await pool.query(
        `INSERT INTO drivers(id,user_id,name,phone,status,is_online,is_active,primary_vehicle_type_id)
         VALUES(?,?,?,?, 'AVAILABLE',1,1,?)`,
        [row.id, row.id, `QA driver ${row.id}`, row.phone, sedan.id],
      );
      await pool.query(
        'INSERT INTO driver_vehicles(driver_id,vehicle_type_id,plate_number,is_primary) VALUES(?,?,?,1)',
        [row.id, sedan.id, `QA-SK-${row.id}`],
      );
    }
  }
  await pool.query('UPDATE booking_driver_assignments SET is_active=0 WHERE driver_id IN (10,11)');
}

const manual = (pickup) => ({
  origin: { address: 'SK origin', name: 'O', lat: 13.69, lng: 100.75 },
  destination: { address: 'SK dest', name: 'D', lat: 12.93, lng: 100.88 },
  vehicleTypeCode: 'SEDAN',
  serviceTypeCode: 'CITY_TRANSFER',
  payoutAmount: 850,
  paymentCollection: 'DRIVER_COLLECTS',
  customer: { name: 'Socket guest', phone: '0888111222' },
  passengers: { adults: 1, children: 0, infants: 0 },
  scheduledPickupAt: pickup,
});

const customerBody = (pickup) => ({
  bookingMode: 'STANDARD',
  serviceTypeCode: 'CITY_TRANSFER',
  vehicleTypeCode: 'SEDAN',
  scheduledPickupAt: pickup,
  destinationRegion: 'Socket QA',
  origin: { name: 'O', address: 'O', placeId: `sk-${randomUUID()}`, lat: 13.7563, lng: 100.5018 },
  destination: { name: 'D', address: 'D', placeId: `sk-${randomUUID()}`, lat: 13.9813, lng: 100.5018 },
  passengers: { adults: 1, children: 0, infants: 0 },
  customer: { name: 'Socket Cust', phone: '0888333444', email: 'qa-socket@example.com' },
});

(async () => {
  await seed();
  const adminToken = sign({ id: 1, role: 'ADMIN', email: 'qa-oc-admin@example.invalid' });
  const customerToken = sign({ id: 2, role: 'CUSTOMER', email: 'qa-oc-customer@example.invalid' });

  const fixture = {
    executedAt: new Date().toISOString(),
    gate: GATE,
    socketDriverUserId: SOCKET_DRIVER_USER_ID,
    socketDriverId: SOCKET_DRIVER_USER_ID,
    pickups: {
      customerStandard: '2029-03-01T09:00:00+07:00',
      adminManual: '2029-03-01T11:00:00+07:00',
    },
    bookings: {},
  };

  if (!GATE) {
    fixture.note = 'Bookings created during socket instrumented step F (after listener registered)';
  } else {
    const pending = await api('POST', '/bookings', {
      body: customerBody('2029-04-01T09:00:00+07:00'),
      headers: { 'Idempotency-Key': randomUUID() },
      status: 201,
    });
    fixture.bookings.gateTruePending = pending.bookingNumber;
    const guest = pending.guestAccessToken;
    await api('POST', `/bookings/${pending.bookingNumber}/contact-connections`, {
      token: customerToken, body: { channel: 'LINE' }, status: 200,
      headers: { 'x-guest-access-token': guest },
    });
    await api('POST', `/bookings/${pending.bookingNumber}/contact-connections/confirm-sent`, {
      token: customerToken, status: 200, headers: { 'x-guest-access-token': guest },
    });
    fixture.pickups.gateTrueAdminManual = '2029-04-01T14:00:00+07:00';
    fixture.note = 'Admin manual for gate=true created in instrumented run after pending observation';
  }

  require('node:fs').writeFileSync(OUT, JSON.stringify(fixture, null, 2));
  console.log(JSON.stringify(fixture, null, 2));
})().catch((e) => {
  console.error('SOCKET_FIXTURE_FAIL', e.stack);
  process.exitCode = 1;
}).finally(() => pool.end());
