const test = require('node:test');
const assert = require('node:assert/strict');
const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  normalizeMarketingAttribution,
  sanitizeUtmValue,
  looksLikePii,
} = require('../src/utils/marketingAttribution.util');

test('normalizeMarketingAttribution stores snake_case touches', () => {
  const normalized = normalizeMarketingAttribution({
    firstTouch: {
      source: 'naver_blog',
      medium: 'organic',
      campaign: 'airport_pattaya',
      landingPage: '/booking',
      referrerHost: 'blog.naver.com',
      capturedAt: '2026-09-02T10:00:00.000Z',
    },
    lastTouch: {
      source: 'naver_blog',
      medium: 'organic',
      campaign: 'airport_pattaya',
      content: 'post_001',
      landingPage: '/booking',
      referrerHost: 'blog.naver.com',
      capturedAt: '2026-09-02T10:05:00.000Z',
    },
  });

  assert.equal(normalized.first_touch.source, 'naver_blog');
  assert.equal(normalized.last_touch.content, 'post_001');
  assert.equal(normalized.first_touch.landing_page, '/booking');
});

test('sanitize drops PII-like utm values instead of failing booking', () => {
  const normalized = normalizeMarketingAttribution({
    firstTouch: {
      source: 'user@example.com',
      medium: 'organic',
      capturedAt: '2026-09-02T10:00:00.000Z',
    },
  });
  assert.equal(normalized.first_touch.source, null);
  assert.equal(normalized.first_touch.medium, 'organic');
  assert.equal(looksLikePii('user@example.com'), true);
  assert.equal(sanitizeUtmValue('valid_campaign'), 'valid_campaign');
});

test('createBookingSchema accepts marketingAttribution and ignores unknown nested keys via service sanitize', () => {
  const payload = {
    bookingMode: 'STANDARD',
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    scheduledPickupAt: new Date(Date.now() + 3 * 60 * 60 * 1000).toISOString(),
    origin: { address: 'BKK Airport' },
    destination: { address: 'Pattaya Hotel' },
    passengers: { adults: 2 },
    customer: { name: 'Test User', phone: '+66812345678' },
    marketingAttribution: {
      firstTouch: {
        source: 'google',
        medium: 'cpc',
        capturedAt: '2026-09-02T10:00:00.000Z',
        email: 'secret@example.com',
      },
    },
  };

  const { error, value } = createBookingSchema.validate(payload);
  assert.equal(error, undefined);
  const normalized = normalizeMarketingAttribution(value.marketingAttribution);
  assert.equal(normalized.first_touch.source, 'google');
  assert.equal(normalized.first_touch.email, undefined);
});

test('invalid landing page with query is dropped', () => {
  const normalized = normalizeMarketingAttribution({
    firstTouch: {
      landingPage: '/booking?utm=x',
      capturedAt: '2026-09-02T10:00:00.000Z',
    },
  });
  assert.equal(normalized, null);
});
