const test = require('node:test');
const assert = require('node:assert/strict');
const BookingRepository = require('../src/repositories/booking.repository');
const { createBookingSchema } = require('../src/validators/booking.validator');
const { registerSchema } = require('../src/validators/auth.validator');
const { createSupportInquirySchema } = require('../src/validators/supportInquiry.validator');
const { resolveEmailLocale } = require('../src/templates/customerEmail');

test('customer booking, registration and inquiry accept Russian without widening invalid locales', () => {
  for (const schema of [createBookingSchema, registerSchema, createSupportInquirySchema]) {
    assert.equal(schema.extract('locale').validate('ru').error, undefined);
    assert(schema.extract('locale').validate('invalid').error);
  }
});

test('Russian booking locale takes priority, is retained for guests and members, and preserves existing fallback', async () => {
  const repo = new BookingRepository();
  const calls = [];
  const conn = { query: async (sql, params) => { calls.push({ sql, params }); return [[{ locale: 'en' }]]; } };
  assert.equal(await repo.resolveBookingLocale(conn, null, 'ru'), 'ru');
  assert.equal(calls.length, 0);
  assert.equal(await repo.resolveBookingLocale(conn, 2, 'ru'), 'ru');
  assert.deepEqual(calls.at(-1).params, ['ru', 2]);
  assert.equal(await repo.resolveBookingLocale(conn, 2), 'en');
  assert.equal(await repo.resolveBookingLocale(conn, null, 'unsupported'), 'ko');
});

test('Russian booking metadata uses the existing English email fallback without new send behavior', () => {
  assert.equal(resolveEmailLocale({ booking_metadata: { locale: 'ru' }, recipient_locale: 'ru' }), 'en');
});
