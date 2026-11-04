const {test}=require('node:test'),assert=require('node:assert/strict');
const Service=require('../src/services/adminDispatch.service'),request=require('supertest'),jwt=require('jsonwebtoken');
const container=require('../src/helpers/container'),app=require('../src/app');
const service=(pool={},drivers={})=>new Service(pool,{},drivers,{}, {driverHasBlockingSettlement:async()=>false});
test('read-only driver detail allowlists fields',async()=>{
 const s=service({}, {listForAdminAssignment:async q=>{assert.equal(q.driverId,6);return [{id:6,name:'QA',phone:'QA',status:'OFFLINE',is_active:1,bank_account:'HIDDEN'}]},listVehiclesByDriverId:async()=>[{id:3,plate_number:'QA123',is_primary:1,is_active:1,insurance:'HIDDEN'}]});
 const r=await s.getDriverDetail(6);assert.equal(r.vehicles[0].plateNumber,'QA123');assert(!JSON.stringify(r).includes('HIDDEN'));
});
test('missing driver returns 404; archived driver can be inspected',async()=>{
 const s=service({}, {listForAdminAssignment:async q=>q.archived?[{id:6}]:[],listVehiclesByDriverId:async()=>[]});assert.equal((await s.getDriverDetail(6)).driverId,6);
 s.driverRepository.listForAdminAssignment=async()=>[];await assert.rejects(()=>s.getDriverDetail(6),e=>e.statusCode===404);
});
test('photos bind to current assignment exact vehicle, safe categories and no writes',async()=>{
 const s=service({query:async(sql,p)=>{for(const str of ['v.id = a.driver_vehicle_id','v.driver_id = a.driver_id','a.is_active = 1','da.vehicle_plate_number = v.plate_number','DRIVER_VEHICLE_PHOTO'])assert(sql.includes(str));assert(!/UPDATE|INSERT|DELETE FROM/i.test(sql));assert.deepEqual(p,['TX209901010206',null,null]);return [[{id:8,mime_type:'image/png',file_path:'PRIVATE'}]];}});
 const r=await s.getCustomerBriefPhotos('TX209901010206');assert.equal(r[0].fileId,8);assert(!JSON.stringify(r).includes('PRIVATE'));
});
test('missing/unassigned/unrelated file returns no photo',async()=>{
 const s=service({query:async()=>[[]]});assert.deepEqual(await s.getCustomerBriefPhotos('TX209901010206'),[]);await assert.rejects(()=>s.getCustomerBriefPhotos('TX209901010206',999),e=>e.statusCode===404);
});
test('actual routes enforce roles and URL contract',async()=>{
 let count=0;container.register('adminDispatchService',()=>({getDriverDetail:async id=>{count++;return {driverId:id}},getCustomerBriefPhotos:async()=>[]}));
 const token=role=>jwt.sign({sub:1,role,type:'access'},process.env.JWT_ACCESS_SECRET,{expiresIn:'1h'});
 for(const path of ['/api/v1/admin/drivers/6','/api/v1/admin/bookings/TX209901010206/customer-brief/photos','/api/v1/admin/bookings/TX209901010206/customer-brief/photos/8']){
 assert.equal((await request(app).get(path)).status,401);assert.equal((await request(app).get(path).set('Authorization','Bearer '+token('DRIVER'))).status,403);}
 const admin='Bearer '+token('ADMIN');assert.equal((await request(app).get('/api/v1/admin/drivers/6').set('Authorization',admin)).status,200);assert.equal((await request(app).get('/api/v1/admin/bookings/TX209901010206/customer-brief/photos').set('Authorization',admin)).status,200);assert.equal(count,1);
 assert.equal((await request(app).get('/api/v1/admin/bookings/TX209901010206/customer-brief/photos/0').set('Authorization',admin)).status,400);
});
