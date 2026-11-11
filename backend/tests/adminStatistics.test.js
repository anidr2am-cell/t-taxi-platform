const { test } = require('node:test');
const assert = require('node:assert/strict');
const { dateRange, getStatistics, summarize } = require('../src/services/adminStatistics.service');

test('Bangkok calendar dates reject invalid or overly broad ranges', () => {
  for (const [from, to] of [
    ['2026-02-29', '2026-03-01'],
    ['2026-12-01', '2026-11-30'],
    ['2026-01-01', '2027-01-02'],
    [['2026-01-01'], '2026-01-01'],
  ]) {
    assert.throws(() => dateRange(from, to), { errorCode: 'STATISTICS_INVALID_RANGE' });
  }
  assert.equal(dateRange('2024-01-01', '2024-12-31').until, '2025-01-01');
});

test('daily, monthly and contact groups preserve trip and passenger counts', () => {
  const result = summarize([
    { day: '2026-10-31', phoneHint: '+8210', flight: '7C2551', service: 'AIRPORT_PICKUP', bookings: '2', passengers: '4', nameSign: '2' },
    { day: '2026-11-02', phoneHint: '00821', flight: '7C2551', service: 'AIRPORT_PICKUP', bookings: '1', passengers: '2' },
    { day: '2026-11-02', phoneHint: '+1202', service: 'GOLF_TRANSFER', bookings: 1, passengers: 3, golfDriver: 1 },
    { day: '2026-11-02', phoneHint: null, service: 'CITY_TRANSFER', bookings: 1, passengers: 1, femaleDriver: 1, coupon: 1 },
  ], dateRange('2026-10-31', '2026-11-02'));
  assert.deepEqual(result.daily.map(r => r.bookings), [2, 0, 3]);
  assert.deepEqual(result.monthly.map(r => r.passengers), [4, 6]);
  assert.deepEqual(result.totals, {
    bookings: 5, passengers: 10, options: { nameSign: 2, femaleDriver: 1, golfDriver: 1, coupon: 1 },
  });
  assert.deepEqual(result.countries.map(r => [r.key, r.passengers]), [['+82', 6], ['+1', 3], [null, 1]]);
  assert.equal(result.flights[0].bookings, 3);
  assert.equal(result.services.length, 3);
  assert.doesNotMatch(JSON.stringify(result), /phoneHint|8210|00821|1202/);
});

test('SQL uses inclusive Bangkok dates with an exclusive upper bound and filters ended trips', async () => {
  const data = await getStatistics('2026-12-31', '2026-12-31', {
    async query(sql, params) {
      assert.deepEqual(params, ['2026-12-31 00:00:00', '2027-01-01 00:00:00']);
      assert.match(sql, /b\.scheduled_pickup_at >= \? AND b\.scheduled_pickup_at < \?/);
      assert.match(sql, /b\.status IN \('SETTLEMENT_PENDING', 'COMPLETED'\)/);
      return [[]];
    },
  });
  assert.equal(data.daily.length, 1);
  assert.equal(data.totals.bookings, 0);
});
