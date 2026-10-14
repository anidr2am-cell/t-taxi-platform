const { test } = require('node:test');
const assert = require('node:assert/strict');
const LandingDataService = require('../../src/services/landingData.service');

function fixture() {
  let clock = Date.parse('2026-10-14T00:00:00Z'), calls = 0;
  const dependencies = {
    now: () => clock,
    routeRepository: { findAll: async () => [
      { isActive: true, serviceTypeCode: 'AIRPORT_PICKUP', originLocationCode: 'BKK', destinationLocationCode: 'PATTAYA', originDisplayName: 'BKK', destinationDisplayName: 'Pattaya', createdBy: 123 },
      { isActive: false, originLocationCode: 'PRIVATE' },
      { isActive: true, effectiveFrom: '2099-01-01' },
    ] },
    vehicleRepository: { findActiveTypesOrdered: async () => [{ code: 'SEDAN', max_passengers: 2 }, { code: 'VIP_SUV' }] },
    pricingService: { calculate: async input => { calls++; assert.equal(input.vehicleCount, 1); assert.deepEqual(input.options, {}); return { totalAmount: 1000 }; } },
    platformSettingsService: { getContactChannelsPublic: async () => ({ channels: [{ code: 'LINE', addUrl: 'https://line.me/example', secret: 'never-public' }] }) },
  };
  return { service: new LandingDataService(dependencies), dependencies, calls: () => calls, advance: () => { clock += 300_000; } };
}
test('public whitelist excludes inactive routes, capacity, internal rows and secrets', async () => {
  const f = fixture(), data = await f.service.get();
  assert.equal(data.rows.length, 1);
  assert.deepEqual(data.rows[0].prices, { SEDAN: 1000 });
  assert.doesNotMatch(JSON.stringify(data), /createdBy|max_passengers|PRIVATE|secret|never-public|VIP_SUV/);
});
test('five-minute cache coalesces concurrent requests and expires', async () => {
  const f = fixture();
  await Promise.all([f.service.get(), f.service.get()]); assert.equal(f.calls(), 1);
  await f.service.get(); assert.equal(f.calls(), 1);
  f.advance(); await f.service.get(); assert.equal(f.calls(), 2);
});
test('invalid quotes fail without poisoning the cache', async () => {
  const f = fixture(); f.dependencies.pricingService.calculate = async () => ({ totalAmount: null });
  await assert.rejects(f.service.get(), /unavailable/);
  f.dependencies.pricingService.calculate = async () => ({ totalAmount: 1000 });
  assert.equal((await f.service.get()).rows[0].prices.SEDAN, 1000);
});
