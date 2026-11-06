const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const Notification=require('../src/services/notification.service');
const FlightRepo=require('../src/repositories/flightMonitor.repository');
test('queued booking edit notification is skipped after reassignment, with no delivery to the old driver',async()=>{
 const repo={isGateArrivalCurrent:async()=>false,findById:async()=>({id:1,type:'CUSTOMER_BOOKING_UPDATED',booking_id:1,recipient_driver_id:2,payload:{assignmentId:10}}),findDeliveriesByNotificationId:async()=>[{id:2,delivery_status:'PENDING'}]};
 const svc=new Notification({},repo,{}, {},{},{});let count=0;svc.recordDeliveryResult=async(n,d,result)=>{count++;assert.equal(result.status,'SKIPPED');assert.equal(result.error,'PERMANENT_BOOKING_CHANGE_ASSIGNMENT_CHANGED');};await svc.processDeliveries(1);assert.equal(count,1);
});
test('web push click opens the driver web for a booking edit notification',async()=>{
 const events={};let wait,opened;
 vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../../frontend/web/firebase-messaging-sw.js'),'utf8'),{URL,self:{location:{origin:'https://qa.example'},addEventListener:(name,cb)=>events[name]=cb},clients:{matchAll:async()=>[],openWindow:async url=>{opened=url;}}});
 events.notificationclick({notification:{data:{notificationType:'CUSTOMER_BOOKING_UPDATED'},close(){}},waitUntil:p=>{wait=p;}});await wait;assert.equal(opened,'https://qa.example/driver');
});
test('stale flight provider result cannot overwrite a customer-corrected flight',async()=>{
 const r=new FlightRepo({});let sql,params;const result=await r.updateFlightSync({query:async(s,p)=>{sql=s;params=p;return [{affectedRows:0}];}},1,{},'KE651');assert.equal(result,false);assert.match(sql,/flight_number = \?/);assert.deepEqual(params.slice(-2),['KE651','KE651']);
});
