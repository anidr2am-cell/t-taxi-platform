const test = require('node:test');
const assert = require('node:assert/strict');
const NotificationService = require('../src/services/notification.service');
const NotificationRepository = require('../src/repositories/notification.repository');
const { EmailNotificationAdapter } = require('../src/services/notificationDelivery.adapters');
const { emailPolicyError } = require('../src/policies/notificationEmail.policy');
const { renderCustomerEmail, copy } = require('../src/templates/customerEmail');
const TYPES = require('../src/constants/notificationTypes');

// Exercise the real repository's transaction/SQL decisions and service dispatch.
// The booking-row mutex models separate concurrent database connections.
function harness({ started = false, failSmtp = false, historical = [] } = {}) {
  const rows = []; const sent = []; const other = []; const sqlLog = [];
  let tail = Promise.resolve();
  const pool = { async getConnection() {
    let releaseLock;
    return {
      async beginTransaction() {},
      async query(sql, params) {
        sqlLog.push(sql);
        if (sql.startsWith('SELECT id FROM bookings')) {
          const previous = tail;
          tail = new Promise((resolve) => { releaseLock = resolve; });
          await previous;
          return [[{ id: 1 }]];
        }
        if (sql.startsWith('SELECT delivery_status')) return [[rows.find((r) => r.delivery.id === params[0]).delivery]];
        if (sql.includes('SELECT n.type')) return [[...historical, ...rows.filter((r) => r.n.audience_role === 'CUSTOMER'
          && (r.delivery.delivery_status === 'DELIVERED' || r.delivery.last_error?.startsWith('PERMANENT_EMAIL_'))).map((r) => ({ type: r.n.type }))]];
        if (sql.includes('COUNT(*) AS n FROM booking_status_logs')) return [[{ n: started ? 1 : 0 }]];
        if (sql.startsWith('INSERT INTO notification_email_attempts')) return [{ insertId: 1 }];
        if (sql.startsWith('UPDATE notification_email_attempts')) return [{ affectedRows: 1 }];
        if (sql.includes("last_error = 'PERMANENT_EMAIL_SEND_RESERVED'")) {
          const d = rows.find((r) => r.delivery.id === params[0]).delivery;
          d.attempt_count++; d.last_error = 'PERMANENT_EMAIL_SEND_RESERVED';
          return [{ affectedRows: 1 }];
        }
        if (sql.includes('UPDATE notification_deliveries')) {
          const [status, increment, error, at, id] = params;
          const d = rows.find((r) => r.delivery.id === id).delivery;
          Object.assign(d, { delivery_status: status, last_error: error, delivered_at: at, attempt_count: d.attempt_count + increment });
          return [{ affectedRows: 1 }];
        }
        throw Error(`Unexpected SQL: ${sql}`);
      },
      async commit() { releaseLock?.(); releaseLock = null; },
      async rollback() { releaseLock?.(); releaseLock = null; },
      release() { releaseLock?.(); },
    };
  } };
  const repo = new NotificationRepository(pool);
  repo.findById = async (id) => rows.find((r) => r.n.id === id).n;
  repo.findDeliveriesByNotificationId = async (id) => {
    const row = rows.find((r) => r.n.id === id);
    return [{ ...row.delivery }, ...['IN_APP', 'FCM'].map((channel) => ({ id: `${id}-${channel}`, channel, delivery_status: 'PENDING' }))];
  };
  const update = repo.updateDeliveryStatus.bind(repo);
  repo.updateDeliveryStatus = async (conn, id, status, error, at, increment) => {
    if (typeof id === 'number') await update(conn, id, status, error, at, increment);
  };
  const adapters = {
    EMAIL: { async send(n) { sent.push(n); if (failSmtp) throw Error('timeout after SMTP acceptance unknown'); return { status: 'DELIVERED' }; } },
    IN_APP: { async send(n) { other.push(['IN_APP', n.type]); return { status: 'DELIVERED' }; } },
    FCM: {},
  };
  const service = new NotificationService(pool, repo, {}, {}, {}, {}, adapters);
  service.sendFcmToActiveDevices = async (n) => { other.push(['FCM', n.type]); return { status: 'DELIVERED' }; };
  function add(type, role = 'CUSTOMER') {
    const id = rows.length + 1;
    rows.push({ n: { id, booking_id: 1, audience_role: role, type }, delivery: {
      id, channel: 'EMAIL', delivery_status: 'PENDING', attempt_count: 0, last_error: null,
    } });
    return id;
  }
  async function flow(types, role) { for (const type of types) await service.processDeliveries(add(type, role)); }
  return { rows, sent, other, service, repo, pool, add, flow, sqlLog };
}

const normal = ['BOOKING_CREATED', 'BOOKING_CONFIRMED', 'DRIVER_ASSIGNED', 'TRIP_ON_ROUTE', 'DRIVER_ARRIVED', 'TRIP_PICKED_UP', 'TRIP_ENDED', 'TRIP_COMPLETED'];
for (const [name, flow, expected] of [
  ['normal', normal, ['BOOKING_CREATED', 'TRIP_ENDED']],
  ['cancelled before trip', ['BOOKING_CREATED', 'DRIVER_ASSIGNED', 'BOOKING_CANCELLED'], ['BOOKING_CREATED', 'BOOKING_CANCELLED']],
  ['no show', ['BOOKING_CREATED', 'DRIVER_ASSIGNED', 'BOOKING_NO_SHOW'], ['BOOKING_CREATED']],
]) test(`${name}: exact customer EMAIL count, IN_APP/FCM unchanged`, async () => {
  const h = harness(); await h.flow(flow);
  assert.deepEqual(h.sent.map((n) => n.type), expected);
  assert.equal(h.other.filter(([channel]) => channel === 'IN_APP').length, flow.length);
  assert.equal(h.other.filter(([channel]) => channel === 'FCM').length, flow.length);
  assert(h.rows.filter((r) => r.delivery.delivery_status === 'DELIVERED').every((r) => r.delivery.attempt_count === 1));
});
test('all driver email types blocked, admins unchanged, independent password-reset path retained', async () => {
  const driver = harness(); await driver.flow(Object.keys(TYPES), 'DRIVER'); assert.equal(driver.sent.length, 0);
  assert.equal(driver.other.length, Object.keys(TYPES).length * 2);
  const admin = harness(); await admin.flow(Object.keys(TYPES), 'ADMIN'); assert.equal(admin.sent.length, Object.keys(TYPES).length);
  const fs = require('node:fs');
  const source = fs.readFileSync(require.resolve('../src/services/driverPasswordResetEmail.service'), 'utf8');
  assert(source.includes('transport.sendMail')); assert(!source.includes('notificationEmail.policy'));
});
test('concurrent duplicate events reserve only one receipt and one terminal email', async () => {
  const h = harness();
  await Promise.all([h.service.processDeliveries(h.add('BOOKING_CREATED')), h.service.processDeliveries(h.add('BOOKING_CREATED'))]);
  await Promise.all([h.service.processDeliveries(h.add('TRIP_ENDED')), h.service.processDeliveries(h.add('BOOKING_CANCELLED'))]);
  assert.equal(h.sent.length, 2);
  assert(h.sqlLog.some((sql) => sql.includes('FROM bookings') && sql.includes('FOR UPDATE')));
});
test('same delivery processed concurrently or recovered after uncertain SMTP is never sent twice', async () => {
  for (const failSmtp of [false, true]) {
    const h = harness({ failSmtp }); const id = h.add('BOOKING_CREATED');
    await Promise.all([h.service.processDeliveries(id), h.service.processDeliveries(id)]);
    await h.service.processDeliveries(id);
    await h.service.processDeliveries(h.add('BOOKING_CREATED'));
    assert.equal(h.sent.length, 1);
  }
});
test('historical customer deliveries count toward the cap; cancellation after trip start is blocked', async () => {
  const capped = harness({ historical: [{ type: 'DRIVER_ASSIGNED' }, { type: 'TRIP_PICKED_UP' }] });
  await capped.flow(['BOOKING_CREATED', 'TRIP_ENDED']); assert.equal(capped.sent.length, 0);
  const started = harness({ started: true }); await started.flow(['BOOKING_CREATED', 'BOOKING_CANCELLED']);
  assert.deepEqual(started.sent.map((n) => n.type), ['BOOKING_CREATED']);
  assert.equal(started.rows[1].delivery.last_error, 'EMAIL_POLICY_CANCELLATION_AFTER_START');
});
test('queued driver email is skipped before adapter/SMTP; explicit admin role wins', async () => {
  const h = harness(); await h.flow(['DRIVER_CALL_AVAILABLE'], 'DRIVER');
  assert.equal(h.rows[0].delivery.delivery_status, 'SKIPPED');
  assert.equal(h.rows[0].delivery.last_error, 'EMAIL_POLICY_DRIVER_DISABLED');
  assert.equal(emailPolicyError({ audience_role: 'ADMIN', recipient_user_role: 'DRIVER', type: 'BOOKING_CREATED' }), null);
});
test('adapter itself cannot send disabled types even when called outside the notification worker', async () => {
  let calls = 0;
  const adapter = new EmailNotificationAdapter({ smtp: { host: 'smtp.example', fromEmail: 'qa@example.com' }, transport: { async sendMail() { calls++; } } });
  for (const type of Object.keys(TYPES)) {
    const result = await adapter.send({ audience_role: 'DRIVER', type, recipient_email: 'qa@example.com' });
    assert.equal(result.status, 'SKIPPED');
  }
  const disabled = await adapter.send({ audience_role: 'CUSTOMER', type: 'TRIP_COMPLETED', recipient_email: 'qa@example.com' });
  assert.equal(disabled.status, 'SKIPPED'); assert.equal(calls, 0);
});
test('notification persistence keeps all channels but disables EMAIL only for disallowed audiences/types', async () => {
  const inserts = [];
  const repo = {
    async findByIdempotencyKey() { return null; }, async insert() { return 1; },
    async findDeliveryByNotificationAndChannel() { return null; },
    async insertDelivery(_conn, row) { inserts.push(row); },
  };
  const service = new NotificationService({}, repo, {}, {}, {}, {}, {});
  for (const audienceRole of ['CUSTOMER', 'DRIVER', 'ADMIN']) {
    inserts.length = 0;
    await service.persistDirectNotificationTx({}, { eventId: 'qa', notificationType: 'DRIVER_ASSIGNED',
      recipientType: 'USER', userId: 1, bookingId: 1, audienceRole, payload: {} });
    assert.equal(inserts.length, 3);
    assert(inserts.filter((r) => r.channel !== 'EMAIL').every((r) => r.deliveryStatus === 'PENDING'));
    assert.equal(inserts.find((r) => r.channel === 'EMAIL').deliveryStatus, audienceRole === 'ADMIN' ? 'PENDING' : 'SKIPPED');
  }
});
test('customer mail without a booking cannot bypass the per-booking cap', async () => {
  const h = harness(); const id = h.add('BOOKING_CREATED'); h.rows[0].n.booking_id = null;
  await h.service.processDeliveries(id); assert.equal(h.sent.length, 0);
  assert.equal(h.rows[0].delivery.last_error, 'EMAIL_POLICY_BOOKING_REQUIRED');
});
for (const locale of ['ko', 'en', 'th', 'ja', 'zh']) test(`receipt includes selected vehicle/payment and policy in ${locale}, manual bookings included`, () => {
  for (const method of ['PAY_DRIVER', 'BANK_TRANSFER', 'CARD']) {
    const n = { type: 'BOOKING_CREATED', audience_role: 'CUSTOMER', recipient_type: 'GUEST_BOOKING',
      booking_number: 'QA_MANUAL', booking_vehicle_type: 'SEDAN', scheduled_pickup_at: '2026-10-18 14:00:00',
      origin_address: 'BKK', destination_address: 'Pattaya', booking_total_amount: '1000.00',
      booking_metadata: { locale, customerPayment: { method } } };
    const message = renderCustomerEmail(n); const t = copy[locale];
    for (const value of ['QA_MANUAL', '2026-10-18 14:00', 'BKK → Pattaya', t.vehicles.SEDAN, t.paymentMethods[method], t.fare, t.cancel, t.payment, t.support, '/booking/lookup']) assert(message.text.includes(value), value);
  }
});
