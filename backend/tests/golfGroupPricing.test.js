const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const Pricing=require('../src/services/pricing.service');
const Golf=require('../src/services/golfPricing.service');
const courses=require('../src/constants/golfCourses.seed.json');
const prices=require('../src/constants/golfPrices.seed.json');
const {pricingCalculateSchema}=require('../src/validators/pricing.validator');
const regions=[{code:'PATTAYA',fare_location_code:'PATTAYA',geometry:{type:'Circle',lat:12.9236,lng:100.8825,radiusKm:20},priority:30,is_active:1},
 {code:'SIRACHA',fare_location_code:'PATTAYA',geometry:{type:'Circle',lat:13.154,lng:100.98,radiusKm:20},priority:20,is_active:1},
 {code:'BKK',airport_iata:'BKK',fare_location_code:'BKK',geometry:{type:'Circle',lat:13.69,lng:100.75,radiusKm:3},priority:100,is_active:1}];
function service() {
 const pricing=new Pricing(null,null,null,null,{findActivePolicies:async()=>[
   {id:1,chargeType:'NAME_SIGN',calculationType:'FIXED',amount:100,isActive:true},
   ...['WAITING','PARKING','TOLL'].map((chargeType,i)=>({id:i+2,chargeType,calculationType:'FIXED',amount:900,isActive:true}))
 ]},{findTypeByCode:async code=>({id:1,code})});
 pricing.golfPricingService=new Golf({findCourse:async id=>courses[id-1]?{...courses[id-1],id,name:courses[id-1].names.en}:null,
   findPrice:async(g,v,h)=>prices[g]?.[v]?{id:1,price:prices[g][v][[18,27,36].indexOf(h)]}:null},
 {list:async()=>regions},pricing);
 return pricing;
}
function input(group='A',vehicle='SEDAN',holes=18,tripType='ROUND_TRIP') {
 const i=courses.findIndex(c=>c.fareGroup===group),c=courses[i];
 return {serviceTypeCode:'GOLF_TRANSFER',vehicleTypeCode:vehicle,originLocationCode:'PATTAYA',destinationRegion:'PATTAYA',
   originLat:12.9477908,originLng:100.8968352,destinationLat:c.lat,destinationLng:c.lng,golf:{courseId:i+1,tripType,holes}};
}
test('24 courses match the exact blog A/B/C membership, with unique codes and coordinate sources',()=>{
 assert.equal(courses.length,24);assert.equal(new Set(courses.map(c=>c.code)).size,24);
 const blog=fs.readFileSync(path.join(__dirname,'../../blog/posts/pattaya-golf-transfer-price.md'),'utf8');
 for(const g of ['A','B','C']) {
   const section=blog.split(`### ${g}그룹`)[1].split('\n##')[0];
   const names=[...section.matchAll(/^- (.+)$/gm)].map(m=>m[1].trim());
   assert.deepEqual(courses.filter(c=>c.fareGroup===g).map(c=>c.names.ko),names);
 }
 for(const c of courses){assert.match(c.coordinateSource,/^https:\/\//);for(const lang of ['ko','en','th'])assert(c.names[lang]);}
});
for(const group of ['A','B','C'])for(const vehicle of ['SEDAN','SUV','VAN'])for(const [i,holes]of [18,27,36].entries()){
 test(`${group}/${vehicle}/${holes} round trip equals blog`,async()=>{
   const q=await service().calculate(input(group,vehicle,holes));assert.equal(q.totalAmount,prices[group][vehicle][i]);assert.equal(q.chargeItems.length,1);
   const blog=fs.readFileSync(path.join(__dirname,'../../blog/posts/pattaya-golf-transfer-price.md'),'utf8');
   const row=blog.split('\n').find(s=>s.startsWith(`| ${group} |`)).split('|').slice(2,-1).map(s=>Number(s.trim().replaceAll(',','')));
   assert.equal(q.totalAmount,row[['SEDAN','SUV','VAN'].indexOf(vehicle)*3+i]);
 });
}
for(const group of ['A','B','C'])for(const vehicle of ['SEDAN','SUV','VAN'])test(`${group}/${vehicle} outbound and return equal half 18-hole regardless of holes`,async()=>{
 const request=input(group,vehicle,36,'OUTBOUND');const s=service();
 assert.equal((await s.calculate(request)).totalAmount,prices[group][vehicle][0]/2);
 const reverse={...request,originLat:request.destinationLat,originLng:request.destinationLng,destinationLat:request.originLat,destinationLng:request.originLng,golf:{...request.golf,tripType:'RETURN'}};
 assert.equal((await s.calculate(reverse)).totalAmount,prices[group][vehicle][0]/2);
});
test('airport, Bangkok hotel, missing choices, unknown course and false destination require 422',async()=>{
 const q=input(),s=service();
 for(const r of [{...q,originAirportIata:'BKK'},{...q,originLat:13.735,originLng:100.56},
   {...q,golf:null},{...q,golf:{...q.golf,holes:null}},{...q,golf:{...q.golf,courseId:999}},
   {...q,destinationLat:13.735,destinationLng:100.56}, {...q,originLat:null}])
   await assert.rejects(s.calculate(r),{statusCode:422,errorCode:'INQUIRY_REQUIRED'});
});
test('included flags ignored; name sign remains +100; vehicle count multiplies fare only',async()=>{
 const q=await service().calculate({...input(),vehicleCount:2,options:{waiting:true,toll:true,parking:true,nameSign:true}});
 assert.equal(q.totalAmount,3300);assert.deepEqual(q.chargeItems.map(c=>c.chargeType),['VEHICLE_BASE','NAME_SIGN']);
});
test('golf request validates explicit round-trip holes, and allows one-way without holes',()=>{
 assert(!pricingCalculateSchema.validate(input()).error);
 assert(pricingCalculateSchema.validate({...input(),golf:{courseId:1,tripType:'ROUND_TRIP'}}).error);
 assert(!pricingCalculateSchema.validate({...input(),golf:{courseId:1,tripType:'OUTBOUND'}}).error);
});
