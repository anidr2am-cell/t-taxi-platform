const { test } = require('node:test');
const assert = require('node:assert/strict');
const Service = require('../src/services/customerGateArrival.service');
const { formatInstantAsServiceDateTime } = require('../src/utils/serviceDateTime.util');
const { renderCustomerEmail } = require('../src/templates/customerEmail');
const { emailPolicyError } = require('../src/policies/notificationEmail.policy');

function fixture(overrides = {}) {
  const events = [], stored = new Map();
  const booking = { id:1, booking_number:'TX202611050001', status:'DRIVER_ASSIGNED', service_type_code:'AIRPORT_PICKUP', scheduled_pickup_at:formatInstantAsServiceDateTime(new Date()), ...overrides };
  let assignment = { id:10, driver_id:2, user_id:20, status:'ONLINE' };
  let sign = false, authorized = true, deliveryFails = false;
  const conn = { beginTransaction:async()=>events.push('begin'), commit:async()=>events.push('commit'), rollback:async()=>events.push('rollback'), release:()=>events.push('release'),
    query:async(sql)=>[sql.includes('booking_charge_items') ? (sign?[{id:1}]:[]) : assignment ? [assignment] : []] };
  const notificationService = {
    notificationRepository:{findByIdempotencyKey:async(_,key)=>stored.get(key)},
    persistDirectNotificationTx:async(_,spec,content)=>{ events.push({spec,content}); stored.set(spec.idempotencyKey,{id:5,read_at:null}); return {notificationId:5}; },
    processDeliveries:async()=>{events.push('delivery');if(deliveryFails)throw Error('offline');},
  };
  const service = new Service({getConnection:async()=>conn}, {
    findByBookingNumberForUpdate:async()=>booking,
    findTransferByBookingId:async()=>({airport_iata:overrides.airport || 'BKK'}),
  },{assertCustomerOrGuestAccess:async()=>{if(!authorized)throw Error('forbidden');}},notificationService);
  return {service,events,stored,booking, setAssignment:v=>assignment=v, setSign:v=>sign=v, setAuthorized:v=>authorized=v, failDelivery:()=>deliveryFails=true};
}
test('GET never queues an alert',async()=>{const f=fixture();assert.equal((await f.service.run('n',null,'t')).available,true);assert.equal(f.stored.size,0);});
test('POST sends Thai only to current assigned driver, commits before delivery; no contacts',async()=>{
  const f=fixture();const result=await f.service.run('n',null,'t',true);assert.equal(result.sent,true);
  const {spec,content}=f.events.find(e=>e.spec);assert.equal(spec.userId,20);assert.equal(spec.recipientDriverId,2);
  assert.match(content.contentOverride.body,/ประตู 7/);assert.deepEqual(Object.keys(spec.payload).sort(),['airport','assignmentId','bookingNumber','gate']);
  assert.ok(f.events.indexOf('commit')<f.events.indexOf('delivery'));
  assert.match(emailPolicyError({audience_role:'DRIVER',type:spec.notificationType}),/EMAIL_POLICY/);
});
test('repeat POST and GET after refresh do not duplicate',async()=>{const f=fixture();await f.service.run('n',null,'t',true);await f.service.run('n',null,'t',true);assert.equal(f.events.filter(e=>e.spec).length,1);assert.equal((await f.service.run('n',null,'t')).sent,true);});
test('read marker is distinct from departure/confirmation',async()=>{const f=fixture();await f.service.run('n',null,'t',true);f.stored.get('gate-arrival:1:10').read_at='2026-11-05';assert.equal((await f.service.run('n',null,'t')).notificationRead,true);assert.equal(f.booking.status,'DRIVER_ASSIGNED');});
test('unauthorized customer/guest cannot query or send',async()=>{for(const send of [false,true]){const f=fixture();f.setAuthorized(false);await assert.rejects(f.service.run('n',null,null,send),/forbidden/);assert.equal(f.stored.size,0);}});
test('DMK, UTP, other service and name-sign Gate 3 cannot send Gate 7',async()=>{
  for(const o of [{airport:'DMK'},{airport:'UTP'},{service_type_code:'AIRPORT_DROPOFF'}])await assert.rejects(fixture(o).service.run('n',null,'t',true),/NOT_APPLICABLE/);
  const f=fixture();f.setSign(true);await assert.rejects(f.service.run('n',null,'t',true),/NOT_APPLICABLE/);
});
test('unassigned/suspended/terminal reservations rejected',async()=>{
  const f=fixture();f.setAssignment(null);await assert.rejects(f.service.run('n',null,'t',true),/UNAVAILABLE/);
  f.setAssignment({id:1,driver_id:2,status:'SUSPENDED'});await assert.rejects(f.service.run('n',null,'t',true),/UNAVAILABLE/);
  for(const status of ['PICKED_UP','SETTLEMENT_PENDING','COMPLETED','CANCELLED','NO_SHOW'])await assert.rejects(fixture({status}).service.run('n',null,'t',true),/UNAVAILABLE/);
});
test('far future cannot pretend to have arrived',async()=>{await assert.rejects(fixture({scheduled_pickup_at:'2099-01-01 12:00:00'}).service.run('n',null,'t',true),/OUTSIDE_PICKUP_WINDOW/);});
test('push failure keeps durable sent status, retry cannot duplicate',async()=>{const f=fixture();f.failDelivery();assert.equal((await f.service.run('n',null,'t',true)).sent,true);await f.service.run('n',null,'t',true);assert.equal(f.stored.size,1);});
test('reassignment uses new assignment key and only its driver',async()=>{const f=fixture();await f.service.run('n',null,'t',true);f.setAssignment({id:11,driver_id:6,user_id:60,status:'ONLINE'});assert.equal((await f.service.run('n',null,'t')).sent,false);await f.service.run('n',null,'t',true);assert.equal(f.events.filter(e=>e.spec).at(-1).spec.userId,60);});
test('queued alert for an old assignment is skipped during recovery',async()=>{
  const NotificationService=require('../src/services/notification.service');
  const repo={isGateArrivalCurrent:async()=>false,findById:async()=>({id:1,type:'CUSTOMER_GATE_ARRIVED',booking_id:1,recipient_driver_id:2,payload:{assignmentId:10}}),
    findDeliveriesByNotificationId:async()=>[{id:2,delivery_status:'PENDING',channel:'FCM'}]};
  const service=new NotificationService({query:async()=>[[]]},repo,{}, {}, {}, {});
  const results=[];service.recordDeliveryResult=async(...args)=>results.push(args[2]);
  await service.processDeliveries(1);
  assert.deepEqual(results,[{status:'SKIPPED',error:'PERMANENT_GATE_ARRIVAL_ASSIGNMENT_CHANGED'}]);
});
test('MariaDB JSON text is converted into the driver inbox object contract',async()=>{
  const Repository=require('../src/repositories/notification.repository');
  const NotificationService=require('../src/services/notification.service');
  const repo=new Repository({query:async()=>[[{id:1,type:'CUSTOMER_GATE_ARRIVED',
    title:'ลูกค้าถึงประตู 7 แล้ว',body:'QA',payload:'{"bookingNumber":"TX209901010217","gate":"7"}',read_at:null}]]});
  const rows=await repo.findNotifications({userId:20},{limit:20,offset:0});
  const item=new NotificationService({},repo,{}, {}, {}, {}).mapListItem(rows[0]);
  assert.equal(typeof item.payload,'object');
  assert.equal(item.payload.bookingNumber,'TX209901010217');
  assert.equal(item.read,false);
});
test('confirmation email has localized authenticated lookup link, no bearer secrets; ended mail unchanged',()=>{
  for(const locale of ['ko','en','th','ja','zh']){
    const n={type:'DRIVER_ASSIGNED',booking_number:'TX202611050001',booking_metadata:{locale}};
    const mail=renderCustomerEmail(n);assert.match(mail.text,/arrival=gate7/);assert.match(mail.html,/arrival=gate7/);assert.match(mail.text,new RegExp('lang='+locale));assert.doesNotMatch(mail.text,/guestAccessToken/);
    assert.doesNotMatch(renderCustomerEmail({...n,type:'TRIP_ENDED'}).text,/arrival=gate7/);
  }
});
