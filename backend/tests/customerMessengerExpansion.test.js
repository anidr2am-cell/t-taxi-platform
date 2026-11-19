const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),crypto=require('node:crypto');
const {createBookingSchema}=require('../src/validators/booking.validator');
const {normalizeMessengerType}=require('../src/utils/customerMessengerFields');
const {resolveBookingContactChannel}=require('../src/utils/bookingContactChannel');
const PlatformSettings=require('../src/services/platformSettings.service');
const {startContactConnectionSchema}=require('../src/validators/bookingContactConnection.validator');
const request=customer=>({serviceTypeCode:'AIRPORT_PICKUP',vehicleTypeCode:'SEDAN',scheduledPickupAt:new Date(Date.now()+86400000).toISOString(),origin:{address:'QA BKK'},destination:{address:'QA Hotel'},passengers:{adults:1},customer:{name:'QA',...customer}});
for(const type of ['WECHAT','TELEGRAM'])test(type+' keeps phone mandatory, optional ID/email persist and connection channel is accepted',()=>{
 assert.equal(normalizeMessengerType(type.toLowerCase()),type);
 assert(createBookingSchema.validate(request({messengerType:type})).error);
 const input={messengerType:type,phone:'+821012345678',email:'qa@example.com'};
 const valid=createBookingSchema.validate(request(input));assert.equal(valid.error,undefined);assert.equal(valid.value.customer.email,input.email);assert.equal(valid.value.customer.messengerType,type);
 assert.equal(createBookingSchema.validate(request({...input,messengerId:'qa_user'})).error,undefined);
 assert(createBookingSchema.validate(request({...input,email:'not-an-email'})).error);
 assert.equal(startContactConnectionSchema.validate({channel:type}).error,undefined);
});
test('public channels resolve to QR-based WeChat and configured Telegram; old settings clients preserve Telegram',async()=>{
 const values={contactWechatEnabled:'true',contactTelegramEnabled:'true',contactTelegramAddUrl:'https://t.me/TRider_taxi'};
 const repo={async findByGroup(){return Object.entries(values).map(([key_name,value])=>({key_name,value}))},async findByGroupAndKey(){return null},async upsert(_g,k,v){values[k]=v}};
 const service=new PlatformSettings(repo),channels=await service.buildContactChannelsPublic(values);
 assert.equal(resolveBookingContactChannel('WECHAT',{channels}),'WECHAT');assert.equal(resolveBookingContactChannel('TELEGRAM',{channels}),'TELEGRAM');
 assert.equal(channels.find(c=>c.code==='TELEGRAM').addUrl,'https://t.me/TRider_taxi');
 const qr=await service.getImage('contactWechatQr');assert(fs.readFileSync(qr).subarray(0,3).equals(Buffer.from([255,216,255])));
 await service.updateContactChannels({contactLineEnabled:false},1);assert.equal(values.contactTelegramEnabled,'true');assert.equal(values.contactTelegramAddUrl,'https://t.me/TRider_taxi');
 assert.equal(resolveBookingContactChannel('TELEGRAM',{defaultChannel:'LINE',channels:[{code:'LINE',addUrl:'https://line.me/test'}]}),'LINE');
});
test('legacy SMS is still accepted for already-open clients',()=>assert.equal(createBookingSchema.validate(request({messengerType:'SMS',messengerId:'+821012345678',phone:'+821012345678'})).error,undefined));
test('member notification email uses the booking-entered address before profile fallback; other roles keep their own address',async()=>{
 const Repo=require('../src/repositories/notification.repository');let sql='';await new Repo({async query(q){sql=q;return [[{id:1,payload:'{}'}]]}}).findById(1);
 assert(sql.includes("WHEN n.recipient_type = 'USER' AND u.role = 'CUSTOMER'"));
 assert(sql.includes("THEN COALESCE(NULLIF(TRIM(b.customer_email), ''), u.email)"));
 assert(sql.includes("WHEN n.recipient_type = 'USER' THEN u.email"));
});
