// Run from the backend directory inside the disposable tride-qa-admin-api container.
// Uses real HTTP, validators, services, repositories, and MariaDB. Never production.
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const requireBackend = createRequire(`${process.cwd()}/package.json`);
assert.equal(process.env.DB_HOST, 'tride-qa-admin-db');
assert.equal(process.env.DB_NAME, 'tride_qa_admin');
const { pool } = requireBackend('./src/config/database');
let server;
(async () => {
  const [[users]] = await pool.query('SELECT COUNT(*) n FROM users');
  if (users.n === 0) {
    await pool.query("INSERT INTO users(id,email,role,is_active) VALUES(1,'qa-admin@example.invalid','ADMIN',1),(4,'qa-driver@example.invalid','DRIVER',1)");
    const [[vehicle]] = await pool.query("SELECT id FROM vehicle_types WHERE code='SEDAN'");
    assert.ok(vehicle, 'Import service and vehicle catalogs first');
    await pool.query("INSERT INTO drivers(id,user_id,name,phone,status,is_online,is_active,primary_vehicle_type_id) VALUES(2,4,'QA test','1111111','AVAILABLE',1,1,?)", [vehicle.id]);
    await pool.query("INSERT INTO driver_vehicles(driver_id,vehicle_type_id,plate_number,is_primary) VALUES(2,?,'QA-ONLY',1)", [vehicle.id]);
  }
  const [[unexpected]] = await pool.query("SELECT COUNT(*) n FROM users WHERE email NOT IN ('qa-admin@example.invalid','qa-driver@example.invalid')");
  assert.equal(unexpected.n, 0, 'Refuse to run with non-QA accounts');
  const [[admin]] = await pool.query("SELECT id FROM users WHERE email='qa-admin@example.invalid'");
  assert.ok(admin, 'Seed disposable QA accounts first');
  await pool.query('UPDATE booking_driver_assignments SET is_active=0 WHERE driver_id=2');
  const app = requireBackend('./src/app');
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/v1/admin`;
  const token = requireBackend('jsonwebtoken').sign(
    { sub: admin.id, role: 'ADMIN', email: 'qa-admin@example.invalid', type: 'access' },
    process.env.JWT_ACCESS_SECRET, { expiresIn: '10m' },
  );
  async function req(method, path, body, status = 200) {
    const response = await fetch(base + path, {
      method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await response.json();
    assert.equal(response.status, status, JSON.stringify({ method, path, response: json }));
    return status >= 400 ? json : json.data;
  }
  const template = {
    origin: { address: 'QA airport', name: 'QA Origin', lat: 13.69, lng: 100.75 },
    destination: { address: 'QA destination', name: 'QA Destination', lat: 12.93, lng: 100.88 },
    vehicleTypeCode: 'SEDAN', serviceTypeCode: 'CITY_TRANSFER', payoutAmount: 850,
    paymentCollection: 'DRIVER_COLLECTS', customer: { name: 'QA isolated guest', phone: '0000000000' },
    passengers: { adults: 2, children: 1, infants: 1 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 2, golfBags: 1, specialItems: 'wheelchair foldable' },
    preferFemaleDriver: true, memo: 'QA initial',
  };
  const create = async time => (await req('POST', '/bookings/manual', { ...template, scheduledPickupAt: time }, 201)).bookingNumber;
  const booking = await create('2026-10-10T10:00:00+07:00');
  const detail = b => req('GET', `/bookings/${b}`);
  let d = await detail(booking);
  assert.equal(Number(d.pricing.totalAmount), 850);
  assert.equal(d.luggage.specialItems, 'wheelchair foldable');
  assert.equal(new Date(d.scheduledPickupAt).toISOString(), '2026-10-10T03:00:00.000Z');
  console.log('PASS create/detail luggage, amount, UTC+7');
  const preserved = x => JSON.stringify({ luggage: x.luggage, passengers: x.passengers, customer: x.customer, route: x.route, options: x.options, pricing: x.pricing });
  const before = preserved(d);
  await req('PATCH', `/bookings/${booking}/manual`, { memo: 'QA memo only' });
  d = await detail(booking);
  assert.equal(d.specialRequests, 'QA memo only');
  assert.equal(preserved(d), before);
  console.log('PASS memo-only preserves fields');
  await req('PATCH', `/bookings/${booking}/manual`, { luggage: { carriers20Inch: 3, specialItems: 'foldable stroller' }, passengers: { children: 2 }, preferFemaleDriver: false });
  d = await detail(booking);
  assert.equal(d.luggage.carriers20Inch, 3);
  assert.equal(d.luggage.carriers24InchPlus, 2);
  assert.equal(d.luggage.specialItems, 'foldable stroller');
  assert.equal(d.passengers.adults, 2);
  assert.equal(d.passengers.children, 2);
  assert.equal(d.options.preferFemaleDriver, false);
  console.log('PASS luggage/passengers partial save and reread');
  await req('PATCH', `/bookings/${booking}/manual`, { serviceTypeCode: 'AIRPORT_PICKUP', originAirportIata: 'BKK', transfer: { flightNumber: 'TG123', airportIata: 'BKK', flightScheduledArrivalAt: '2026-10-10T02:00:00Z', flightEstimatedArrivalAt: '2026-10-10T02:15:00Z' } });
  d = await detail(booking);
  assert.equal(d.flight.flightNumber, 'TG123');
  assert.equal(new Date(d.flight.estimatedArrivalAt).toISOString(), '2026-10-10T02:15:00.000Z');
  await req('PATCH', `/bookings/${booking}/manual`, { memo: 'QA flight preservation' });
  assert.deepEqual((await detail(booking)).flight, d.flight);
  console.log('PASS flight ETA save and memo-only preservation');
  await req('PATCH', `/bookings/${booking}/manual`, { transfer: { golfRegion: 'QA Region', driverIncluded: true } });
  d = await detail(booking);
  assert.equal(d.flight.golfRegion, 'QA Region');
  assert.equal(d.flight.driverIncluded, true);
  assert.equal(d.flight.flightNumber, 'TG123');
  assert.equal(new Date(d.flight.estimatedArrivalAt).toISOString(), '2026-10-10T02:15:00.000Z');
  console.log('PASS golf partial update preserves flight and ETA');
  await req('POST', `/bookings/${booking}/assign-driver`, { driverId: 2 });
  const boundary = await create('2026-10-10T11:00:00+07:00');
  const allowed = await create('2026-10-10T11:00:01+07:00');
  for (const [b, conflict] of [[boundary, true], [allowed, false]]) {
    const list = await req('GET', `/drivers?bookingNumber=${b}`);
    const driver = (Array.isArray(list) ? list : list.items).find(x => x.driverId === 2);
    assert.ok(driver);
    assert.equal(Boolean(driver.pickupTimeConflict), conflict);
  }
  console.log('PASS listDrivers 60:00 conflict, 60:01 eligible');
  const error = await req('POST', `/bookings/${boundary}/assign-driver`, { driverId: 2 }, 409);
  assert.equal(error.error_code, 'DRIVER_BOOKING_TIME_CONFLICT');
  await req('POST', `/bookings/${allowed}/assign-driver`, { driverId: 2 });
  const [[assignments]] = await pool.query('SELECT COUNT(*) n FROM booking_driver_assignments WHERE driver_id=2 AND is_active=1');
  assert.equal(assignments.n, 2);
  console.log('PASS assign 60:00 HTTP409; 60:01 HTTP200 with active job');
  console.log(JSON.stringify({ result: 'PASS', bookings: [booking, boundary, allowed], activeAssignments: assignments.n }));
})().catch(error => { console.error('QA_FAIL', error.stack); process.exitCode = 1; }).finally(async () => {
  if (server) await new Promise(resolve => server.close(resolve));
  await pool.end();
});
