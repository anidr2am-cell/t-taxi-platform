const {createHash,randomUUID}=require('node:crypto');
const Parent=require('./adminReceiptEmail.service');
const AppError=require('../utils/AppError');
const {encrypt}=require('../utils/tokenEncryption.util');
const {renderCustomerEmail}=require('../templates/customerEmail');
function meta(value){try{return typeof value==='string'?JSON.parse(value)||{}:value||{}}catch{return {}}}
function fail(code){throw new AppError(code,{statusCode:409,errorCode:code})}
const ACTIVE=new Set(['OPEN','PENDING','CONFIRMED','DRIVER_ASSIGNED','ON_ROUTE','DRIVER_ARRIVED','PICKED_UP']);
class AdminBookingEmailService extends Parent {
  eligibility(row,history){
    if(!ACTIVE.has(row.status))return 'RECEIPT_EMAIL_BOOKING_NOT_ACTIVE';
    const m=meta(row.metadata);
    if(m.adminBookingConfirmationEmail?.approvedAt || m.adminReceiptEmail?.approvedAt)return 'RECEIPT_EMAIL_ALREADY_APPROVED';
    const original=history.filter(h=>h.type==='BOOKING_CREATED');
    // This feature only repairs a missing-address notification, never retries SMTP.
    if(original.some(h=>h.delivery_status==='DELIVERED'||Number(h.accepted_confirmed)||Number(h.smtp_attempts)
      || Number(h.attempt_count)>0 && !['PERMANENT_INVALID_RECIPIENT','CONFIG_MISSING'].includes(h.last_error)))return 'RECEIPT_EMAIL_EXISTING_ATTEMPT';
    if(history.filter(h=>h.delivery_status==='DELIVERED'||Number(h.accepted_confirmed)||Number(h.smtp_attempts)).length>=2)return 'RECEIPT_EMAIL_LIMIT';
    return null;
  }
  state(row,history){
    const m=meta(row.metadata),prior=m.adminBookingConfirmationEmail;
    const delivery=prior?history.find(h=>Number(h.id)===Number(prior.deliveryId)):history.find(h=>h.type==='BOOKING_CREATED');
    const reason=this.eligibility(row,history);
    return {eligible:!reason,reason,email:row.customer_email||'',locale:require('../templates/customerEmail').normalizeLocale(m.locale)||'en',
      configured:Boolean(this.notificationService.adapters.EMAIL?.isConfigured()),
      delivery:delivery?{deliveryId:delivery.id,status:delivery.delivery_status,outcome:delivery.outcome||null}:null,approvedAt:prior?.approvedAt||null};
  }
  async document(row,input){
    const n={type:'BOOKING_CREATED',audience_role:'CUSTOMER',recipient_type:'GUEST_BOOKING',booking_number:row.booking_number,
      booking_metadata:{...meta(row.metadata),locale:input.locale},booking_status:row.status,booking_total_amount:row.total_amount,
      booking_currency:row.currency,booking_payment_status:row.payment_status,booking_payment_method:row.payment_method,
      booking_vehicle_type:row.vehicle_type_code,scheduled_pickup_at:row.scheduled_pickup_at,
      origin_address:row.origin_address,destination_address:row.destination_address,created_at:this.now().toISOString()};
    const output=renderCustomerEmail(n,{origin:this.notificationService.adapters.EMAIL?.customerWebOrigin});
    const previewHash=createHash('sha256').update(JSON.stringify({email:input.email,status:row.status,output})).digest('hex');
    return {...output,email:input.email,previewHash};
  }
  async send(number,input,actor){
    this.authorize(actor);const parsed=this.validate(input);
    if(input.confirmed!==true)fail('RECEIPT_EMAIL_CONFIRM_REQUIRED');
    if(!this.notificationService.adapters.EMAIL?.isConfigured())fail('RECEIPT_EMAIL_UNAVAILABLE');
    const conn=await this.pool.getConnection();let id;
    try{
      await conn.beginTransaction();
      const {row,history}=await this.context(number,conn,true);
      const reason=this.eligibility(row,history);if(reason)fail(reason);
      const doc=await this.document(row,parsed);if(!input.previewHash||input.previewHash!==doc.previewHash)fail('RECEIPT_EMAIL_PREVIEW_CHANGED');
      const key=createHash('sha256').update('ADMIN_BOOKING_CONFIRMATION_EMAIL:'+row.id).digest('hex');
      if(await this.notifications.findByIdempotencyKey(conn,key))fail('RECEIPT_EMAIL_ALREADY_APPROVED');
      id=await this.notifications.insertEmailOnly(conn,{recipientType:'GUEST_BOOKING',bookingId:row.id,audienceRole:'CUSTOMER',
        eventId:randomUUID(),eventName:'ADMIN_BOOKING_EMAIL_APPROVED',idempotencyKey:key,notificationType:'BOOKING_CREATED',
        title:doc.subject,body:'Administrator-approved missing booking email',payload:{adminBookingConfirmation:true,locale:parsed.locale,
          approvedEmail:encrypt(JSON.stringify({to:parsed.email,subject:doc.subject,text:doc.text,html:doc.html}))}});
      const deliveryId=await this.notifications.insertDelivery(conn,{notificationId:id,channel:'EMAIL',deliveryStatus:'PENDING'});
      await this.repo.approveBookingEmail(conn,row,parsed.email,{approvedAt:this.now().toISOString(),actorUserId:actor.id,locale:parsed.locale,notificationId:id,deliveryId});
      await this.bookings.insertActivityLog(conn,row.id,{activityType:'BOOKING_EMAIL_APPROVED',actorUserId:actor.id,actorRole:actor.role,
        description:'Administrator approved missing booking email',payload:{notificationId:id,deliveryId,recipientMasked:parsed.email.replace(/^(.).*(@.*)$/,'$1***$2'),locale:parsed.locale}});
      await conn.commit();
    }catch(e){await conn.rollback();throw e}finally{conn.release()}
    try{await this.notificationService.processDeliveries(id)}catch{ /* The approval and delivery ledger remain authoritative. */ }
    return this.get(number,actor);
  }
}
module.exports=AdminBookingEmailService;
