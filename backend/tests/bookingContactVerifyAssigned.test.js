const test = require('node:test');
const assert = require('node:assert/strict');
const Service = require('../src/services/bookingContactConnection.service');
const { canVerifyContact } = require('../src/policies/adminContactDispatch.policy');
const AdminDispatchService = require('../src/services/adminDispatch.service');

function harness(status, metadata = {}) {
  const booking = { id: 991, booking_number: 'TX202610249991', status,
    contact_status: 'CONFIRM_REQUESTED', contact_channel: 'KAKAO', metadata,
    payment_status: 'UNPAID', total_amount: 1000, scheduled_pickup_at: '2026-10-27 12:00:00' };
  const assignment = Object.freeze({ id: 91, booking_id: 991, driver_id: 2, is_active: 1 });
  const connection = { id: 71, channel: 'KAKAO', status: 'CONFIRM_REQUESTED' };
  let dispatch = 0, updates = 0, lock = Promise.resolve();
  const pool = { async getConnection() {
    let unlock;
    return {
      async beginTransaction() {
        const previous = lock; lock = new Promise(resolve => { unlock = resolve; }); await previous;
      },
      async commit() { unlock(); }, async rollback() { unlock(); }, release() {},
    };
  } };
  const repo = {
    async findByBookingNumberForUpdate() { return { ...booking }; },
    async findById() { return { ...booking }; },
    async findContactBookingByNumber() { return { ...booking }; },
  };
  const contacts = {
    async findActiveByBookingId() { return { ...connection }; },
    async updateConnectionStatus(_c, _id, patch) {
      Object.assign(connection, { status: patch.status, adminVerifiedBy: patch.adminVerifiedBy }); updates++;
    },
    async updateBookingContactSnapshot(_c, _id, patch) {
      booking.contact_status = patch.contactStatus;
      booking.contact_verified_at = patch.contactVerifiedAt;
    },
  };
  const service = new Service(pool, repo, contacts, {
    formatDateTime: () => '2026-10-24 12:00:00',
    // Even a stale retry decision must never dispatch assigned trips.
    needsContactDispatchRetry: () => true,
    isContactDispatchDelivered: m => m?.contactDispatchDelivered === true,
    async dispatchAfterContactVerified() { dispatch++; return true; },
  });
  return { service, booking, connection, assignment, get dispatch() { return dispatch; }, get updates() { return updates; } };
}

for (const status of ['DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP']) {
  for (const metadata of [{}, {contactDispatchCompleted:true, contactDispatchDelivered:true}]) {
    test(status + ' verifies contact only, preserving assignment and never redispatching', async () => {
      const h = harness(status, metadata), before = { ...h.booking }, assignment = { ...h.assignment };
      assert.equal(canVerifyContact(h.booking), true);
      const allowed = AdminDispatchService.prototype.computeAllowedActions(h.booking, h.assignment);
      assert.ok(allowed.includes('VERIFY_CONTACT'));
      const results = await Promise.all([h.service.adminVerify(h.booking.booking_number, 42), h.service.adminVerify(h.booking.booking_number, 42)]);
      assert(results.every(r => r.contactStatus === 'VERIFIED' && r.dispatchStarted === false));
      assert.equal((await h.service.adminVerify(h.booking.booking_number, 42)).dispatchStarted, false);
      assert.equal(h.dispatch, 0); assert.equal(h.updates, 1);
      assert.equal(h.connection.adminVerifiedBy, 42);
      assert.deepEqual(h.assignment, assignment);
      const { contact_status, contact_verified_at, ...rest } = h.booking;
      const { contact_status: old, ...original } = before;
      assert.deepEqual(rest, original);
    });
  }
}
for (const status of ['PENDING','CONFIRMED','SETTLEMENT_PENDING','COMPLETED','CANCELLED','NO_SHOW']) {
  test(status + ' remains ineligible', async () => {
    const h = harness(status);
    assert.equal(canVerifyContact(h.booking), false);
    await assert.rejects(h.service.adminVerify(h.booking.booking_number, 42), e => e.statusCode === 409);
    assert.equal(h.updates, 0); assert.equal(h.dispatch, 0);
  });
}
