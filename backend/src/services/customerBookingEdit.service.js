const {createHash,randomUUID}=require('node:crypto');
const AppError=require('../utils/AppError');
const {normalizeMessengerType}=require('../utils/customerMessengerFields');
const {normalizeFlightNumber}=require('../utils/flightNumber.util');
const Repository=require('../repositories/customerBookingEdit.repository');
const EDITABLE=new Set(['PENDING','OPEN','CONFIRMED','DRIVER_ASSIGNED','ON_ROUTE','DRIVER_ARRIVED']);
function metadata(row){if(row.metadata&&typeof row.metadata==='object')return {...row.metadata};try{return JSON.parse(row.metadata||'{}')||{};}catch(_){return {};}}
function snapshot(row){const m=metadata(row);const fields={phone:row.customer_phone??null,email:row.customer_email??null,messengerType:normalizeMessengerType(m.messengerType),messengerId:m.messengerId??null,flightNumber:row.flight_number??null,specialRequests:row.special_requests??null,changeRequest:m.customerChangeRequest??null};return {...fields,canEdit:EDITABLE.has(row.status),flightEditable:['AIRPORT_PICKUP','AIRPORT_DROPOFF'].includes(row.service_type_code),revision:createHash('sha256').update(JSON.stringify(fields)).digest('hex')};}
const fail=(code,statusCode=409)=>{throw new AppError(code,{errorCode:code,statusCode});};
class CustomerBookingEditService {
 constructor(pool,bookings,bookingService,notifications,repository=new Repository()){Object.assign(this,{pool,bookings,bookingService,notifications,repository});}
 async run(number,user,token,input=null){const conn=await this.pool.getConnection();let deliveryId;
 try {await conn.beginTransaction();const row=await this.repository.find(conn,number);if(!row)fail('BOOKING_NOT_ACCESSIBLE',403);
 await this.bookingService.assertCustomerOrGuestAccess(conn,row,user,token);const before=snapshot(row);
 if(!input){await conn.commit();return before;}
 if(!before.canEdit)fail('BOOKING_EDIT_CLOSED');
 const m=metadata(row),customer=input.customer??{};
 const fields={...before,phone:customer.phone===undefined?before.phone:customer.phone,email:customer.email===undefined?before.email:(customer.email||null),
   messengerType:customer.messengerType===undefined?before.messengerType:normalizeMessengerType(customer.messengerType),
   messengerId:customer.messengerId===undefined?before.messengerId:(customer.messengerId||null),
   flightNumber:input.flightNumber===undefined?before.flightNumber:(normalizeFlightNumber(input.flightNumber)||null),
   specialRequests:input.specialRequests===undefined?before.specialRequests:(input.specialRequests||null)};
 if(['WHATSAPP','SMS'].includes(fields.messengerType)&&customer.phone!==undefined)fields.messengerId=fields.phone;
 const changed=['phone','email','messengerType','messengerId','flightNumber','specialRequests'].filter(k=>fields[k]!==before[k]);
 if(fields.messengerType==='SMS'&&before.messengerType!=='SMS')fail('VALIDATION_ERROR',422);
 if(changed.some(k=>['phone','messengerType','messengerId'].includes(k))){
  if(!/^\+[1-9]\d{6,14}$/.test(fields.phone||''))fail('VALIDATION_ERROR',422);
  if(fields.messengerType==='LINE'&&!fields.messengerId)fail('VALIDATION_ERROR',422);
 }
 if(changed.includes('flightNumber')&&!['AIRPORT_PICKUP','AIRPORT_DROPOFF'].includes(row.service_type_code))fail('VALIDATION_ERROR',422);
 const requestText=input.changeRequest?.trim();const requestChanged=Boolean(requestText&&requestText!==before.changeRequest?.message);
 if(!changed.length&&!requestChanged){await conn.commit();return {...before,changed:false};}
 if(input.revision!==before.revision)fail('BOOKING_EDIT_CONFLICT');
 const eventId=randomUUID();
 m.messengerType=fields.messengerType;m.messengerId=fields.messengerId;
 if(requestChanged)m.customerChangeRequest={message:requestText,requestedAt:new Date().toISOString(),requestId:eventId};
 const resetContact=changed.some(k=>['phone','messengerType','messengerId'].includes(k));
 const next={...fields,metadata:m,contactChannel:resetContact?await this.bookingService.resolveInitialContactChannel({messengerType:fields.messengerType}):row.contact_channel};
 await this.repository.save(conn,row,next,changed.includes('flightNumber'),resetContact);
 const changedFields=[...changed,...(requestChanged?['changeRequest']:[])];
 await this.bookings.insertActivityLog(conn,row.id,{activityType:requestChanged?'CUSTOMER_BOOKING_CHANGE_REQUESTED':'CUSTOMER_BOOKING_UPDATED',actorUserId:user?.id??null,actorRole:'CUSTOMER',description:requestChanged?'Customer requested an itinerary change; not applied automatically':'Customer updated booking details',payload:{changedFields,requestId:eventId}});
 const a=await this.repository.assignment(conn,row.id);
 if(a&&a.status!=='SUSPENDED'){
  const result=await this.notifications.persistDirectNotificationTx(conn,{recipientType:'USER',userId:a.user_id,recipientDriverId:a.driver_id,bookingId:row.id,audienceRole:'DRIVER',notificationType:'CUSTOMER_BOOKING_UPDATED',eventName:'customer.booking_updated',eventId,idempotencyKey:`booking-edit:${row.id}:${eventId}`,payload:{bookingNumber:row.booking_number,assignmentId:a.id,changedFields}},
  {contentOverride:{title:'ลูกค้าอัปเดตข้อมูลการจอง',body:`การจอง ${row.booking_number}: ${requestChanged?'ลูกค้าขอเปลี่ยนรายละเอียดการเดินทาง ยังไม่ยืนยันการเปลี่ยนแปลง โปรดประสานผู้ดูแล':'ลูกค้าอัปเดตข้อมูลติดต่อ เที่ยวบิน หรือคำขอ โปรดเปิดรายละเอียดงานและตรวจสอบกับผู้ดูแล'} ข้อมูลติดต่อลูกค้าให้ติดต่อผ่านผู้ดูแล`}});
  deliveryId=result.notificationId;
 }
 await conn.commit();if(deliveryId)await this.notifications.processDeliveries(deliveryId).catch(()=>{});
 return {...snapshot({...row,customer_phone:next.phone,customer_email:next.email,special_requests:next.specialRequests,flight_number:next.flightNumber,metadata:m}),changed:true,driverNotificationQueued:Boolean(deliveryId)};
 }catch(e){await conn.rollback();throw e;}finally{conn.release();}}
}
module.exports={CustomerBookingEditService,snapshot};
