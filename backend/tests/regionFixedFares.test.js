const test = require('node:test');
const assert = require('node:assert/strict');
const Pricing = require('../src/services/pricing.service');
const { contains, matchRegion } = require('../src/utils/pricingRegion.util');
const regions = [
  { code: 'BKK', fare_location_code: 'BKK', airport_iata: 'BKK', geometry: { type: 'Circle', lat: 13.69, lng: 100.75, radiusKm: 2 }, priority: 100, is_active: 1 },
  { code: 'PATTAYA', fare_location_code: 'PATTAYA', geometry: { type: 'Circle', lat: 12.9236, lng: 100.8825, radiusKm: 15 }, priority: 10, is_active: 1 },
  { code: 'SIRACHA', fare_location_code: 'PATTAYA', geometry: { type: 'Circle', lat: 13.1542112, lng: 100.9836189, radiusKm: 10 }, priority: 20, is_active: 1 },
];
function service() {
  const routes = [{ id: 1, serviceTypeId: 1, originLocationId: 1, destinationLocationId: 8, isActive: true }];
  return new Pricing({ findByCode: async code => ({ id: {AIRPORT_PICKUP:1,AIRPORT_DROPOFF:2,CITY_TRANSFER:3,GOLF_TRANSFER:4}[code], code }) },
    { findByCode: async code => ({ id: code === 'BKK' ? 1 : 8 }) },
    { findActiveByServiceAndLocations: async (s, o, d) => routes.filter(r => r.serviceTypeId === s && r.originLocationId === o && r.destinationLocationId === d) },
    { findByRouteId: async () => ['SEDAN','SUV','VAN'].map((v, i) => ({ id: i + 1, vehicleTypeId: i + 1, isActive: true, price: [1000,1300,1700][i], currency: 'THB' })) },
    { findActivePolicies: async () => ['NAME_SIGN','WAITING','PARKING','TOLL','NIGHT','AIRPORT'].map((chargeType, i) => ({ id: i + 1, chargeType, calculationType: 'FIXED', amount: 100, isActive: true })) },
    { findTypeByCode: async code => ({ id: ['SEDAN','SUV','VAN'].indexOf(code) + 1, code }) },
    null, { list: async () => regions });
}
const input = { serviceTypeCode: 'AIRPORT_PICKUP', vehicleTypeCode: 'SEDAN', originAirportIata: 'BKK', destinationLat: 12.9477908, destinationLng: 100.8968352 };
test('hotels anywhere in the same region have fixed fares; no C-distance path', async () => {
  const s = service(); s.distanceAdjustment = () => { throw Error('C must not run'); };
  for (const [lat,lng] of [[12.9477908,100.8968352],[12.87,100.90],[12.99,100.91]]) {
    for (const [i,v] of ['SEDAN','SUV','VAN'].entries()) {
      const q = await s.calculate({ ...input, vehicleTypeCode: v, destinationLat: lat, destinationLng: lng });
      assert.equal(q.totalAmount, [1000,1300,1700][i]); assert.equal(q.pricingMode, 'REGION_FIXED');
      assert(!q.chargeItems.some(x => x.chargeType === 'DISTANCE_SURCHARGE'));
    }
  }
});
test('Siracha proposal shares Pattaya fare but remains a separate geographical region', async () => {
  const q = await service().calculate({ ...input, destinationLat: 13.1542112, destinationLng: 100.9836189 });
  assert.equal(q.totalAmount,1000); assert.equal(q.destinationRegion,'SIRACHA');
});
test('unmatched geography never falls back to nearest route', async () => {
  const s = service(); s.calculateReferenceRouteQuote = () => { throw Error('fallback forbidden'); };
  await assert.rejects(s.calculate({ ...input, destinationLat: 20, destinationLng: 104 }), { errorCode: 'INQUIRY_REQUIRED' });
});
test('matched geography without a direction-specific fare requires inquiry', async () => {
  const s = service(); s.routeRepository.findActiveByServiceAndLocations = async () => [];
  await assert.rejects(s.calculate(input), { errorCode: 'INQUIRY_REQUIRED' });
});
test('IATA has priority and does not require redundant airport coordinates', async () => {
  assert.equal(matchRegion(regions,0,0,'BKK').code,'BKK');
  assert.equal(matchRegion(regions,13.69,100.75,'UTP'),null);
  assert.equal((await service().calculate(input)).totalAmount,1000);
});
test('included toll parking waiting stay ignored and name sign stays +100', async () => {
  const q = await service().calculate({ ...input, options: { toll:true,parking:true,waiting:true,nameSign:true } });
  assert.equal(q.totalAmount,1100); assert.equal(q.chargeItems.length,2);
});
test('missing coordinates are not silently converted to 0/0', () => {
  assert.equal(matchRegion(regions,null,null),null);
});
test('polygon edge is inclusive and exterior is excluded', () => {
  const r={ geometry:{type:'Polygon',coordinates:[[[0,0],[2,0],[2,2],[0,2],[0,0]]] } };
  assert.equal(contains(r,1,1),true); assert.equal(contains(r,0,1),true); assert.equal(contains(r,3,1),false);
});
test('same-region city preserves the existing calculation', async () => {
  const s=service();s.legacyCalculate=async()=>({legacy:true});
  assert.deepEqual(await s.calculate({ serviceTypeCode:'CITY_TRANSFER', originLat:12.93,originLng:100.89,destinationLat:12.95,destinationLng:100.90 }),{legacy:true});
});

test('golf returns the inquiry contract for every origin with either region flag', async () => {
  for (const regional of [true, false]) {
    const s = service();
    if (!regional) s.pricingRegionRepository = null;
    s.legacyCalculate = async () => { throw Error('legacy golf must not run'); };
    for (const origin of [{originLocationCode:'PATTAYA'}, {originAirportIata:'BKK'}, {originLocationCode:'UNKNOWN'}]) {
      await assert.rejects(s.calculate({ ...input, ...origin, serviceTypeCode:'GOLF_TRANSFER' }),
        { statusCode:422, errorCode:'INQUIRY_REQUIRED' });
    }
  }
});
test('registered landing catalog does not change when geographic policy is enabled', async () => {
  const s=service();s.legacyCalculate=async body=>body;
  assert.deepEqual(await s.calculateRegisteredRoute({originLocationCode:'BKK',destinationLocationCode:'PATTAYA'}),{originLocationCode:'BKK',destinationLocationCode:'PATTAYA'});
});
test('dropoff quote contract accepts destination airport IATA without an invented region', () => {
  const { pricingCalculateSchema } = require('../src/validators/pricing.validator');
  const result = pricingCalculateSchema.validate({ serviceTypeCode:'AIRPORT_DROPOFF',vehicleTypeCode:'SEDAN',originLocationCode:'PATTAYA',destinationAirportIata:'bkk' });
  assert.equal(result.error,undefined); assert.equal(result.value.destinationAirportIata,'BKK');
});
test('the same regional pair keeps its fixed fare across non-golf service selections', async () => {
  for (const serviceTypeCode of ['AIRPORT_PICKUP','AIRPORT_DROPOFF','CITY_TRANSFER']) {
    assert.equal((await service().calculate({...input,serviceTypeCode})).totalAmount,1000);
  }
});

test('approved new regional fares use normal included-cost/name-sign policy and vehicle count', async () => {
  const s = service();
  s.pricingRegionRepository.findFare = async () => ({id:1,price:3000,currency:'THB'});
  const q = await s.calculate({...input,vehicleCount:2,options:{nameSign:true,toll:true,parking:true,waiting:true}});
  assert.equal(q.totalAmount,6100);
  assert.equal(q.routeId,null); assert.equal(q.vehiclePriceId,null);
  assert.equal(q.chargeItems[0].referenceType,'REGION_FARE');
  assert.equal(q.chargeItems[0].referenceId,1);
});

test('approved migration contains 9 regions, 39 fares; Pattaya wins coastal overlap', () => {
  const fs = require('node:fs'); const path = require('node:path');
  const sql=fs.readFileSync(path.join(__dirname,'../../database/75_region_fixed_fare_proposal.sql'),'utf8');
  const section=sql.split('INSERT INTO pricing_regions')[1].split('-- Separate regional additions')[0];
  const seeded=[...section.matchAll(/\('([^']+)','([^']+)',(NULL|'[^']+'),'([^']+)',(\d+),'[^']*'\)/g)]
    .map(m=>({code:m[1],fare_location_code:m[2],geometry:JSON.parse(m[4]),priority:Number(m[5]),is_active:1}));
  assert.equal(seeded.length,9);
  for (const [lat,lng] of [[13.1542112,100.9836189],[13.2751426,100.9288993],[13.3611,100.9847]])
    assert.equal(matchRegion(seeded,lat,lng).code,'SIRACHA');
  assert.equal(matchRegion(seeded,13.088764,100.92392).code,'PATTAYA');
  assert.equal(matchRegion(seeded,12.6664,100.9007),null);
  assert.equal((sql.split('INSERT INTO pricing_region_fares')[1].match(/\('[^']+','[^']+','[^']+',\d+\)/g)||[]).length,39);
  assert(!/\b(?:UPDATE|INSERT INTO)\s+(?:routes|vehicle_prices|bookings|vehicle_capacity_rules)\b/i.test(sql));
});
