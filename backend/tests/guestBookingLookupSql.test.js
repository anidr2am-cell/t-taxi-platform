const test = require('node:test');
const assert = require('node:assert/strict');
const mysql = require('mysql2/promise');
const BookingRepository = require('../src/repositories/booking.repository');
const GuestBookingLookupService = require('../src/services/guestBookingLookup.service');
const { hashToken } = require('../src/utils/tokenHash.util');
const { prepareGuestLookupFixture } = require('./fixtures/guestLookupSqlFixture');

test('shared guest lookup SELECT includes customer name once for every lookup path', () => {
  const repository = new BookingRepository({});
  assert.equal((repository.guestLookupSelectSql().match(/\bb\.customer_name\b/g) ?? []).length, 1);
});

if (process.env.CI === 'true') {
  assert.ok(process.env.GUEST_LOOKUP_TEST_DB, 'CI must run real SQL guest lookup regression');
}

test('real SQL projection, joins, name authentication and guest token transaction', {
  skip: !process.env.GUEST_LOOKUP_TEST_DB,
}, async () => {
  assert.match(process.env.GUEST_LOOKUP_TEST_DB, /^qa_guest_lookup_[a-z0-9_]+$/);
  const pool = mysql.createPool({
    host: process.env.GUEST_LOOKUP_TEST_DB_HOST ?? '127.0.0.1',
    port: Number(process.env.GUEST_LOOKUP_TEST_DB_PORT ?? 3306),
    user: 'root', password: '', database: process.env.GUEST_LOOKUP_TEST_DB,
    dateStrings: true, charset: 'utf8mb4',
  });
  try {
    await prepareGuestLookupFixture(pool);
    const repository = new BookingRepository(pool);
    const service = new GuestBookingLookupService(pool, repository);
    const countTokens = async () => Number((await pool.query('SELECT COUNT(*) AS n FROM guest_access_tokens'))[0][0].n);
    const result = await service.lookup({ bookingNumber: 'TX209901010001', name: '  qa   GUEST example  ' });
    assert.equal(result.customerName, 'QA Guest Example');
    assert.equal(result.status, 'DRIVER_ASSIGNED');
    const [[token]] = await pool.query('SELECT token_hash FROM guest_access_tokens WHERE booking_id=1');
    assert.equal(token.token_hash, hashToken(result.guestAccess.token));
    assert.equal(await countTokens(), 1);
    for (const input of [
      { bookingNumber: 'TX209901010001', name: 'Other guest' },
      { bookingNumber: 'TX209901010002', name: 'QA Guest Example' },
      { bookingNumber: 'TX209901010003', name: 'QA Guest Example' },
      { bookingNumber: 'TX209901019999', name: 'QA Guest Example' },
      { bookingNumber: 'TX209901010001' },
    ]) {
      await assert.rejects(service.lookup(input), { errorCode: 'BOOKING_NOT_FOUND' });
      assert.equal(await countTokens(), 1);
    }
    assert.equal((await service.lookup({ bookingNumber: 'TX209901010004', name: 'QA Guest Example' })).customerName, 'QA Guest Example');
    assert.equal((await service.lookup({ bookingNumber: 'TX209901010005', name: 'ทดสอบ ลูกค้า' })).customerName, 'ทดสอบ ลูกค้า');
    assert.equal((await service.lookup({ bookingNumber: 'TX209901010001', phone: '+66 81 234 5678' })).bookingNumber, 'TX209901010001');
    const beforeContact = await countTokens();
    const contact = await service.lookupByContact({ name: 'QA Guest Example', phone: '+66812345678' });
    assert.equal(contact.privacyLevel, 'CONTACT_LOOKUP');
    assert.equal(contact.bookings.length, 1);
    assert.equal(await countTokens(), beforeContact);
    assert.equal(JSON.stringify(contact).includes('QA Guest Example'), false);
  } finally {
    await pool.end();
  }
});
