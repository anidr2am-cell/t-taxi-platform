process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const PricingService = require('../src/services/pricing.service');
const { estimateRoadDistanceKm } = require('../src/utils/geo.util');


const pairs = [
  {"airport": "BKK", "city": "PATTAYA", "airportPoint": [13.689999, 100.747924], "cityPoint": [12.9236, 100.8825], "prices": {"SEDAN": 1000.0, "SUV": 1300.0, "VAN": 1700.0}},
  {"airport": "BKK", "city": "AYUTTHAYA", "airportPoint": [13.689999, 100.747924], "cityPoint": [14.3532, 100.5689], "prices": {"SEDAN": 1200.0, "SUV": 1400.0, "VAN": 1800.0}},
  {"airport": "BKK", "city": "BANGKOK", "airportPoint": [13.689999, 100.747924], "cityPoint": [13.7563, 100.5018], "prices": {"SEDAN": 550.0, "SUV": 600.0, "VAN": 1100.0}},
  {"airport": "BKK", "city": "HUA_HIN", "airportPoint": [13.689999, 100.747924], "cityPoint": [12.5684, 99.9577], "prices": {"SEDAN": 2000.0, "SUV": 2200.0, "VAN": 2700.0}},
  {"airport": "BKK", "city": "RAYONG", "airportPoint": [13.689999, 100.747924], "cityPoint": [12.6814, 101.2816], "prices": {"SEDAN": 1500.0, "SUV": 1700.0, "VAN": 2100.0}},
  {"airport": "DMK", "city": "BANGKOK", "airportPoint": [13.91326, 100.60201], "cityPoint": [13.7563, 100.5018], "prices": {"SEDAN": 600.0, "SUV": 800.0, "VAN": 1200.0}},
  {"airport": "DMK", "city": "HUA_HIN", "airportPoint": [13.91326, 100.60201], "cityPoint": [12.5684, 99.9577], "prices": {"SEDAN": 2000.0, "SUV": 2200.0, "VAN": 2700.0}},
  {"airport": "DMK", "city": "PATTAYA", "airportPoint": [13.91326, 100.60201], "cityPoint": [12.9236, 100.8825], "prices": {"SEDAN": 1400.0, "SUV": 1600.0, "VAN": 2200.0}},
  {"airport": "DMK", "city": "RAYONG", "airportPoint": [13.91326, 100.60201], "cityPoint": [12.6814, 101.2816], "prices": {"SEDAN": 1800.0, "SUV": 2000.0, "VAN": 2500.0}}
];
const catalog = pairs.flatMap(p => ["SEDAN","SUV","VAN"].map(vehicle => ({origin:p.airport,destination:p.city,originLat:p.airportPoint[0],originLng:p.airportPoint[1],destinationLat:p.cityPoint[0],destinationLng:p.cityPoint[1],vehicle,price:p.prices[vehicle]})));

test('all nine airport/city pairs and representative hotel dropoffs match pickup fares', async () => {
 const locs=new Map(),routes=[];
 for(const r of catalog) {
  for(const [code,lat,lng] of [[r.origin,r.originLat,r.originLng],[r.destination,r.destinationLat,r.destinationLng]])if(!locs.has(code))locs.set(code,{id:locs.size+1,code,latitude:Number(lat),longitude:Number(lng)});
  if(r.origin==='BKK'&&r.destination==='BANGKOK')r.price={SEDAN:500,SUV:600,VAN:1000}[r.vehicle];
 }
 const vehicles=['SEDAN','SUV','VAN'].map((code,i)=>({code,id:i+1}));
 for(const r of catalog)for(const [serviceTypeId,origin,destination] of [[1,r.origin,r.destination],[2,r.destination,r.origin]]) {
  let route=routes.find(x=>x.serviceTypeId===serviceTypeId&&x.originLocationCode===origin&&x.destinationLocationCode===destination);
  if(!route){const a=locs.get(origin),b=locs.get(destination);route={id:routes.length+1,serviceTypeId,originLocationId:a.id,destinationLocationId:b.id,originLocationCode:origin,destinationLocationCode:destination,originLatitude:a.latitude,originLongitude:a.longitude,destinationLatitude:b.latitude,destinationLongitude:b.longitude,isActive:true,prices:{}};routes.push(route);}
  route.prices[r.vehicle]=Number(r.price);
 }
 const service=new PricingService(
  {findByCode:async code=>({id:code==='AIRPORT_PICKUP'?1:2,code})},
  {findByCode:async code=>locs.get(code)},
  {findActiveByServiceAndLocations:async(s,a,b)=>routes.filter(r=>r.serviceTypeId===s&&r.originLocationId===a&&r.destinationLocationId===b)},
  {findByRouteId:async id=>vehicles.map(v=>({id:id*10+v.id,vehicleTypeId:v.id,price:routes.find(r=>r.id===id).prices[v.code],isActive:true,currency:'THB'}))},
  {findActivePolicies:async()=>[]},{findTypeByCode:async code=>vehicles.find(v=>v.code===code)});
 for(const r of routes)for(const v of vehicles) {
  const quote=await service.calculate({serviceTypeCode:r.serviceTypeId===1?'AIRPORT_PICKUP':'AIRPORT_DROPOFF',vehicleTypeCode:v.code,originLocationCode:r.originLocationCode,destinationLocationCode:r.destinationLocationCode,originLat:r.originLatitude,originLng:r.originLongitude,destinationLat:r.destinationLatitude,destinationLng:r.destinationLongitude});
  assert.equal(quote.totalAmount,r.prices[v.code]);assert.ok(!quote.chargeItems.some(c=>c.chargeType==='DISTANCE_SURCHARGE'));
 }
 for(const [origin,dest,coords,prices] of [['BANGKOK','BKK',[13.7155852,100.5905761],[500,600,1000]],['PATTAYA','BKK',[12.9477908,100.8968352],[1000,1300,1700]],['PATTAYA','DMK',[12.9477908,100.8968352],[1400,1600,2200]]])for(const [i,v] of vehicles.entries()) {
  const d=locs.get(dest),q=await service.calculate({serviceTypeCode:'AIRPORT_DROPOFF',vehicleTypeCode:v.code,originLocationCode:origin,destinationLocationCode:dest,originLat:coords[0],originLng:coords[1],destinationLat:d.latitude,destinationLng:d.longitude});
  assert.equal(q.totalAmount,prices[i]);assert.ok(!q.chargeItems.some(c=>c.chargeType==='DISTANCE_SURCHARGE'));
 }
});
