const {test}=require('node:test');
const assert=require('node:assert/strict');
const {airportFromRegions,resolveBookingAirport}=require('../src/utils/bookingAirport.util');
const regions=require('./helpers/airportRegionFixture')();
const bkk={service_type_code:'AIRPORT_PICKUP',origin_lat:'13.689999',origin_lng:'100.747924'};
test('legacy BKK airport coordinates resolve using approved existing boundary, no address guessing',()=>{
 const row={...bkk,airport_iata:null,airport_code_custom:null};const before=JSON.stringify(row);
 assert.equal(airportFromRegions(row,regions),'BKK');assert.equal(JSON.stringify(row),before);
});
for(const [code,lat,lng] of [['DMK',13.91326,100.60201],['UTP',12.679944,101.005028]])test(code+' stays distinct',()=>assert.equal(airportFromRegions({...bkk,origin_lat:lat,origin_lng:lng},regions),code));
test('explicit normalized code wins; malformed explicit code does not infer another airport',()=>{
 assert.equal(airportFromRegions({...bkk,airport_iata:' dmk '},regions),'DMK');
 assert.equal(airportFromRegions({...bkk,airport_code_custom:'UTP'},regions),'UTP');
 assert.equal(airportFromRegions({...bkk,airport_iata:'INVALID'},regions),null);
});
test('name-only, missing/invalid coordinates and outside airport fail closed',()=>{
 for(const point of [{origin_lat:null},{origin_lng:''},{origin_lat:999},{origin_lng:'NaN'},{origin_lat:13.7563,origin_lng:100.5018}])assert.equal(airportFromRegions({...bkk,origin_address:'BKK Suvarnabhumi Airport',...point},regions),null);
});
test('city/nearby fare regions, disabled or malformed boundaries never count',()=>{
 assert.equal(airportFromRegions(bkk,[{...regions[0],airport_iata:null},{...regions[0],is_active:0},{...regions[0],geometry:'broken'}]),null);
});
test('ambiguous airport overlap fails closed',()=>assert.equal(airportFromRegions(bkk,[regions[0],{...regions[0],airport_iata:'DMK'}]),null));
test('dropoff uses destination; city/golf do not infer pickup airport',()=>{
 assert.equal(airportFromRegions({...bkk,service_type_code:'AIRPORT_DROPOFF',destination_lat:bkk.origin_lat,destination_lng:bkk.origin_lng},regions),'BKK');
 for(const service_type_code of ['CITY_TRANSFER','GOLF_TRANSFER'])assert.equal(airportFromRegions({...bkk,service_type_code},regions),null);
});
test('resolver queries only when code is missing and a valid airport-side point exists',async()=>{
 let reads=0;const repo={findActiveAirportRegions:async()=>{reads++;return regions;}};
 assert.equal(await resolveBookingAirport({...bkk,airport_iata:'BKK'},repo),'BKK');assert.equal(reads,0);
 assert.equal(await resolveBookingAirport({...bkk,origin_lat:null},repo),null);assert.equal(reads,0);
 assert.equal(await resolveBookingAirport(bkk,repo),'BKK');assert.equal(reads,1);
});
test('customer lookup enrichment shares resolver and never mutates or writes stored rows',async()=>{
 const Repo=require('../src/repositories/booking.repository');let reads=0;const repo=new Repo({query:async sql=>{assert.match(sql,/SELECT/);assert.doesNotMatch(sql,/UPDATE|INSERT|DELETE/);reads++;return [regions];}});
 const rows=[{...bkk,id:1},{...bkk,id:2,airport_iata:'DMK'}],before=JSON.stringify(rows);
 const mapped=await repo.withResolvedAirport(rows);assert.equal(reads,1);assert.equal(mapped[0].origin_airport_iata,'BKK');assert.equal(mapped[1].origin_airport_iata,'DMK');assert.equal(JSON.stringify(rows),before);
 const Guest=require('../src/services/guestBookingLookup.service');const dto=new Guest({},repo).mapBooking({...mapped[0],booking_number:'QA_1',status:'DRIVER_ASSIGNED'},null,null);
 assert.equal(dto.route.origin.airportIata,'BKK');assert.equal(dto.route.origin.lat,undefined);
});
