const test=require('node:test'),assert=require('node:assert/strict');
const GuestPhoto=require('../src/services/guestVehiclePhoto.service');
const {hashToken}=require('../src/utils/tokenHash.util');
test('voucher portrait requires a token and never uses a user ID alone',async()=>{
 let read=false;
 const svc=new GuestPhoto({findAssignedDriverAvatarFile:async()=>{read=true;}});
 await assert.rejects(()=>svc.getAssignedDriverAvatarFile(12,'', {id:99,role:'DRIVER'}),e=>e.statusCode===403);
 assert.equal(read,false);
});
test('voucher portrait scopes guest authentication to exact booking and token hash',async()=>{
 const svc=new GuestPhoto({findAssignedDriverAvatarFile:async(id,hash)=>id===12&&hash===hashToken('booking12')?{file_path:'qa/avatar.png',mime_type:'image/png'}:null});
 assert.equal((await svc.getAssignedDriverAvatarFile(12,'booking12')).filePath,'qa/avatar.png');
 await assert.rejects(()=>svc.getAssignedDriverAvatarFile(13,'booking12'),e=>e.statusCode===404);
 await assert.rejects(()=>svc.getAssignedDriverAvatarFile(12,'other'),e=>e.statusCode===404);
});
test('voucher portrait checks customer ownership before omitting guest token',async()=>{
 let authorized=0,released=0;
 const repo={findById:async()=>({customer_user_id:7}),findAssignedDriverAvatarFile:async(id,hash)=>{assert.equal(hash,null);return {file_path:'qa/avatar.png'};}};
 const svc=new GuestPhoto(repo,{assertCustomerOrGuestAccess:async()=>authorized++},{getConnection:async()=>({release:()=>released++})});
 await svc.getAssignedDriverAvatarFile(12,'',{id:7,role:'CUSTOMER'});
 assert.equal(authorized,1);assert.equal(released,1);
 await assert.rejects(()=>svc.getAssignedDriverAvatarFile(12,'',{id:8,role:'CUSTOMER'}),e=>e.statusCode===403);
});
test('airport shortcuts are exclusively active registered airport regions',async()=>{
 const Repository=require('../src/repositories/pricingRegion.repository');
 const original=Repository.prototype.list;
 Repository.prototype.list=async()=>[{is_active:1,airport_iata:'BKK'},{is_active:1,airport_iata:'DMK'},{is_active:1,airport_iata:'UTP'},{is_active:0,airport_iata:'CNX'},{is_active:1,airport_iata:null}];
 try {
  const request=require('supertest'),app=require('../src/app');
  const r=await request(app).get('/api/v1/airports');
  assert.equal(r.status,200);assert.deepEqual(r.body.data,[{code:'BKK'},{code:'DMK'},{code:'UTP'}]);
 } finally {Repository.prototype.list=original;}
});
