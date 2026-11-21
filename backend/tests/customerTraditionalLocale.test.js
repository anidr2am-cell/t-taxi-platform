const test = require('node:test');
const assert = require('node:assert/strict');
const BookingRepository = require('../src/repositories/booking.repository');
const { createBookingSchema } = require('../src/validators/booking.validator');
const { registerSchema } = require('../src/validators/auth.validator');
const { createSupportInquirySchema } = require('../src/validators/supportInquiry.validator');

test('Traditional Chinese locale is accepted throughout the customer flow', () => {
  for (const schema of [createBookingSchema, registerSchema, createSupportInquirySchema]) {
    assert.equal(schema.extract('locale').validate('zh-TW').error, undefined);
    assert.equal(schema.extract('locale').validate('zh').error, undefined);
    assert(schema.extract('locale').validate('unknown').error);
  }
});

test('booking-time locale survives for guests and members', async () => {
  const calls = [];
  const conn = { query: async (sql, params) => {
    calls.push({ sql, params });
    return [[{ locale: 'en' }]];
  } };
  const repo = new BookingRepository();
  assert.equal(await repo.resolveBookingLocale(conn, null, 'zh-TW'), 'zh-TW');
  assert.equal(calls.length, 0);
  assert.equal(await repo.resolveBookingLocale(conn, 2, 'zh-TW'), 'zh-TW');
  assert.deepEqual(calls.at(-1).params, ['zh-TW', 2]);
});
