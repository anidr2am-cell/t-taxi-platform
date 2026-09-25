// Creates fresh QA bookings for driver web UI checks (numbers only in manifest).
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const fs = require('node:fs');

assert.equal(process.env.DB_HOST, 'tride-qa-admin-db');
assert.equal(process.env.DB_NAME, 'tride_qa_admin');

const requireBackend = createRequire(`${process.cwd()}/package.json`);
const jwt = requireBackend('jsonwebtoken');
const bcrypt = requireBackend('bcryptjs');
const { pool } = requireBackend('./src/config/database');
const { resolveQaDriverPassword, UI_DRIVER_ROWS } = require('./qa-ui-driver-auth.cjs');

const QA_API = (process.env.QA_API_BASE || 'http://127.0.0.1:3000/api/v1').replace(/\/$/, '');
const GATE = String(process.env.CONTACT_CONNECTION_REQUIRED || 'false').toLowerCase() === 'true';
const OUT = process.env.UI_MANIFEST_PATH || '/srv/tride/backend/ui-manifest.json';

function sign(user) {
  return jwt.sign(
    { sub: user.id, role: user.role, email: user.email, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '60m' },
  );
}

async function api(method, path, { token, body, status = 200, headers = {} } = {}) {
  const h = { 'Content-Type': 'application/json', ...headers };
  if (token) h.Authorization = `Bearer ${token}`;
  const res = await fetch(`${QA_API}${path}`, { method, headers: h, body: body ? JSON.stringify(body) : undefined });
  const json = await res.json();
  assert.equal(res.status, status, JSON.stringify(json));
  return json.data ?? json;
}

async function seedDrivers() {
  const hash = await bcrypt.hash(resolveQaDriverPassword(), 10);
  const [[nAdmin]] = await pool.query('SELECT COUNT(*) c FROM users WHERE id=1');
  if (nAdmin.c === 0) {
    await pool.query(
      `INSERT INTO users(id,email,role,is_active,password_hash) VALUES
       (1,'qa-oc-admin@example.invalid','ADMIN',1,NULL),
       (2,'qa-oc-customer@example.invalid','CUSTOMER',1,NULL)`,
    );
    const [[bands]] = await pool.query('SELECT COUNT(*) n FROM city_transfer_distance_bands');
    if (bands.n === 0) {
      await pool.query(`
        INSERT INTO city_transfer_distance_bands
          (min_km, max_km, sedan_price, suv_price, van_price, currency, is_active)
        VALUES
          (0, 12, NULL, NULL, NULL, 'THB', 1),
          (13, 50, 900, 1100, 1400, 'THB', 1),
          (51, 100, 1100, 1350, 1700, 'THB', 1)`);
    }
    await pool.query(
      `INSERT INTO settings(group_name,key_name,value,data_type) VALUES
       ('contact_channels','contactLineEnabled','true','boolean'),
       ('contact_channels','contactLineDisplayName','QA Line','string'),
       ('contact_channels','contactLineAddUrl','https://line.me/example','string')`,
    );
  }

  const [[sedan]] = await pool.query("SELECT id FROM vehicle_types WHERE code='SEDAN'");
  assert.ok(sedan, 'SEDAN vehicle type required');

  for (const row of UI_DRIVER_ROWS) {
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
        [row.id, sedan.id, `QA-${row.id}`],
      );
    } else {
      await pool.query(
        `UPDATE drivers SET user_id=?, name=?, phone=?, status='AVAILABLE', is_online=1, is_active=1,
         primary_vehicle_type_id=? WHERE id=?`,
        [row.id, `QA driver ${row.id}`, row.phone, sedan.id, row.id],
      );
    }
  }
}

const manual = (pickup) => ({
  origin: { address: 'QA UI origin', name: 'O', lat: 13.69, lng: 100.75 },
  destination: { address: 'QA UI dest', name: 'D', lat: 12.93, lng: 100.88 },
  vehicleTypeCode: 'SEDAN',
  serviceTypeCode: 'CITY_TRANSFER',
  payoutAmount: 850,
  paymentCollection: 'DRIVER_COLLECTS',
  customer: { name: 'UI guest', phone: '0888000099' },
  passengers: { adults: 1, children: 0, infants: 0 },
  scheduledPickupAt: pickup,
});

const customerBody = (pickup) => ({
  bookingMode: 'STANDARD',
  serviceTypeCode: 'CITY_TRANSFER',
  vehicleTypeCode: 'SEDAN',
  scheduledPickupAt: pickup,
  destinationRegion: 'QA UI region',
  origin: { name: 'O', address: 'O', placeId: `ui-${randomUUID()}`, lat: 13.7563, lng: 100.5018 },
  destination: { name: 'D', address: 'D', placeId: `ui-${randomUUID()}`, lat: 13.9813, lng: 100.5018 },
  passengers: { adults: 1, children: 0, infants: 0 },
  customer: { name: 'UI Cust', phone: '0888000088', email: 'qa-ui@example.com' },
});

(async () => {
  await seedDrivers();
  const adminToken = sign({ id: 1, role: 'ADMIN', email: 'qa-oc-admin@example.invalid' });
  const customerToken = sign({ id: 2, role: 'CUSTOMER', email: 'qa-oc-customer@example.invalid' });

  const manifest = {
    executedAt: new Date().toISOString(),
    gate: GATE,
    driverLoginPhone: '1111111',
    apiBaseUrlHost: 'http://127.0.0.1:13001',
    flutterDartDefineApiBaseUrl: 'http://127.0.0.1:13001',
    flutterDartDefineSocketUrl: 'http://127.0.0.1:13001',
    bookings: {},
  };

  if (!GATE) {
    manifest.bookings.gateFalseCustomer = (await api('POST', '/bookings', {
      body: customerBody('2028-10-01T08:00:00+07:00'),
      headers: { 'Idempotency-Key': randomUUID() },
      status: 201,
    })).bookingNumber;
    await pool.query('UPDATE booking_driver_assignments SET is_active=0 WHERE driver_id=10');
    const anchor = await api('POST', '/admin/bookings/manual', {
      token: adminToken, body: manual('2028-10-01T10:00:00+07:00'), status: 201,
    });
    await api('POST', `/admin/bookings/${anchor.bookingNumber}/assign-driver`, {
      token: adminToken, body: { driverId: 10 }, status: 200,
    });
    manifest.bookings.gateFalseBusyPlus61 = (await api('POST', '/admin/bookings/manual', {
      token: adminToken, body: manual('2028-10-01T11:01:00+07:00'), status: 201,
    })).bookingNumber;
    manifest.bookings.gateFalseBusyPlus60 = (await api('POST', '/admin/bookings/manual', {
      token: adminToken, body: manual('2028-10-01T11:00:00+07:00'), status: 201,
    })).bookingNumber;
    manifest.bookings.gateFalseAdminManual = (await api('POST', '/admin/bookings/manual', {
      token: adminToken, body: manual('2028-10-01T14:00:00+07:00'), status: 201,
    })).bookingNumber;
  } else {
    const pending = await api('POST', '/bookings', {
      body: customerBody('2028-11-01T09:00:00+07:00'),
      headers: { 'Idempotency-Key': randomUUID() },
      status: 201,
    });
    manifest.bookings.gateTrueCustomerPending = pending.bookingNumber;
    const guest = pending.guestAccessToken;
    await api('POST', `/bookings/${pending.bookingNumber}/contact-connections`, {
      token: customerToken, body: { channel: 'LINE' }, status: 200,
      headers: { 'x-guest-access-token': guest },
    });
    await api('POST', `/bookings/${pending.bookingNumber}/contact-connections/confirm-sent`, {
      token: customerToken, status: 200, headers: { 'x-guest-access-token': guest },
    });
    manifest.bookings.gateTrueAdminManual = (await api('POST', '/admin/bookings/manual', {
      token: adminToken, body: manual('2028-11-01T11:00:00+07:00'), status: 201,
    })).bookingNumber;
    manifest.note = 'gate=true: run run-ui-gate-true-verify-post.cjs before post-phase API/UI checks';
  }

  delete manifest.driverLoginPassword;
  fs.writeFileSync(OUT, JSON.stringify(manifest, null, 2));
  console.log(JSON.stringify(manifest, null, 2));
})().catch((err) => {
  console.error('UI_FIXTURE_FAIL', err.stack);
  process.exitCode = 1;
}).finally(() => pool.end());
