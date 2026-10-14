process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const { estimateRoadDistanceKm } = require('../src/utils/geo.util');

// Place coordinates were resolved through the production Google Places proxy
// on 2026-10-13. Registered route anchors come from migration 66.
const points = {
  BKK: [13.689999, 100.747924],
  DMK: [13.91326, 100.60201],
  PATTAYA: [12.9236, 100.8825],
  BANGKOK: [13.7563, 100.5018],
  RAYONG: [12.6814, 101.2816],
  SN: [12.9477908, 100.8968352],
  JOMTIEN: [12.8911658, 100.8736814],
  NAKLUA: [12.9523743, 100.8847986],
  J_PARK: [13.1542112, 100.9836189],
  BANGSAEN: [13.2751426, 100.9288993],
  RAYONG_CITY: [12.6813957, 101.2816261],
  SUKHUMVIT: [13.7155852, 100.5905761],
  SILOM: [13.7237445, 100.5295569],
  KHAO_SAN: [13.7581072, 100.4989781],
  DON_MUEANG: [13.9272289, 100.5858593],
  BANG_NA: [13.663853, 100.6132453],
};

const serviceTypes = [
  { id: 1, code: 'AIRPORT_PICKUP' },
  { id: 2, code: 'AIRPORT_DROPOFF' },
  { id: 3, code: 'CITY_TRANSFER' },
];
const locations = [
  { id: 1, code: 'BKK', latitude: points.BKK[0], longitude: points.BKK[1] },
  { id: 2, code: 'DMK', latitude: points.DMK[0], longitude: points.DMK[1] },
  { id: 3, code: 'PATTAYA', latitude: points.PATTAYA[0], longitude: points.PATTAYA[1] },
  { id: 4, code: 'BANGKOK', latitude: points.BANGKOK[0], longitude: points.BANGKOK[1] },
  { id: 5, code: 'RAYONG', latitude: points.RAYONG[0], longitude: points.RAYONG[1] },
];
const vehicleTypes = [
  { id: 1, code: 'SEDAN' },
  { id: 2, code: 'SUV' },
  { id: 3, code: 'VAN' },
];

function makeRoute(id, serviceTypeId, originCode, destinationCode, prices) {
  const origin = locations.find((row) => row.code === originCode);
  const destination = locations.find((row) => row.code === destinationCode);
  return {
    id,
    serviceTypeId,
    originLocationId: origin.id,
    originLocationCode: origin.code,
    originLatitude: origin.latitude,
    originLongitude: origin.longitude,
    destinationLocationId: destination.id,
    destinationLocationCode: destination.code,
    destinationLatitude: destination.latitude,
    destinationLongitude: destination.longitude,
    prices,
    isActive: true,
    effectiveFrom: null,
    effectiveTo: null,
  };
}

const routes = [
  makeRoute(1, 1, 'BKK', 'PATTAYA', [1000, 1300, 1700]),
  makeRoute(2, 1, 'BKK', 'BANGKOK', [550, 600, 1100]),
  makeRoute(3, 1, 'BKK', 'RAYONG', [1500, 1700, 2100]),
  makeRoute(4, 1, 'DMK', 'PATTAYA', [1400, 1600, 2200]),
  makeRoute(5, 1, 'DMK', 'BANGKOK', [600, 800, 1200]),
  makeRoute(6, 2, 'PATTAYA', 'BKK', [1000, 1300, 1700]),
  makeRoute(7, 2, 'BANGKOK', 'BKK', [700, 800, 1200]),
  makeRoute(8, 3, 'BANGKOK', 'PATTAYA', [1300, 1600, 2000]),
  makeRoute(9, 3, 'PATTAYA', 'BANGKOK', [1300, 1500, 2000]),
];

function makeService() {
  return new PricingService(
    { async findByCode(code) { return serviceTypes.find((row) => row.code === code) ?? null; } },
    {
      async findById(id) { return locations.find((row) => row.id === Number(id)) ?? null; },
      async findByCode(code) { return locations.find((row) => row.code === code) ?? null; },
      async findByAirportIata(code) { return locations.find((row) => row.code === code) ?? null; },
    },
    {
      async findActiveByServiceAndLocations(serviceTypeId, originId, destinationId) {
        return routes.filter((route) => route.serviceTypeId === serviceTypeId
          && route.originLocationId === originId && route.destinationLocationId === destinationId);
      },
      async findActiveByService(serviceTypeId) {
        return routes.filter((route) => route.serviceTypeId === serviceTypeId);
      },
    },
    {
      async findByRouteId(routeId) {
        const route = routes.find((row) => row.id === routeId);
        return vehicleTypes.map((vehicle, index) => ({
          id: routeId * 10 + vehicle.id,
          routeId,
          vehicleTypeId: vehicle.id,
          price: route.prices[index],
          currency: 'THB',
          isActive: true,
          effectiveFrom: null,
          effectiveTo: null,
        }));
      },
    },
    { async findActivePolicies() { return []; } },
    { async findTypeByCode(code) { return vehicleTypes.find((row) => row.code === code) ?? null; } },
  );
}

test('migration 73 approved city and airport fares retain the C-distance rule', async () => {
 const service=makeService();
 const cases=['SUKHUMVIT','SILOM','KHAO_SAN','BANG_NA'];
 for(const destination of cases)for(const [index,vehicle] of vehicleTypes.entries()) {
  const a=points.BKK,b=points[destination];
  const input={serviceTypeCode:'AIRPORT_PICKUP',vehicleTypeCode:vehicle.code,originLocationCode:'BKK',destinationLocationCode:'BANGKOK',originLat:a[0],originLng:a[1],destinationLat:b[0],destinationLng:b[1]};
  assert.equal((await service.calculate(input)).totalAmount,[550,600,1100][index]);
 }
 routes.find(r=>r.id===2).prices=[500,600,1000];
 routes.push(makeRoute(10,1,'BKK','DMK',[600,700,1000]),makeRoute(11,1,'DMK','BKK',[600,700,1000]));
 for(const [origin,destination] of [...cases.map(d=>['BKK',d]),['BKK','DMK'],['DMK','BKK']])for(const [index,vehicle] of vehicleTypes.entries()) {
  const a=points[origin],b=points[destination],airport=['BKK','DMK'].includes(destination);
  const result=await service.calculate({serviceTypeCode:'AIRPORT_PICKUP',vehicleTypeCode:vehicle.code,originLocationCode:origin,destinationLocationCode:airport?destination:'BANGKOK',originLat:a[0],originLng:a[1],destinationLat:b[0],destinationLng:b[1],options:{toll:true,parking:true,waiting:true}});
  assert.equal(result.totalAmount,(airport?[600,700,1000]:[500,600,1000])[index],origin+' '+destination+' '+vehicle.code);
  assert.ok(!result.chargeItems.some(c=>['DISTANCE_SURCHARGE','TOLL_GATE','WAITING_CHARGE','OTHER'].includes(c.chargeType)));
 }
});
