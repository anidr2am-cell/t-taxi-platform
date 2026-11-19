const {createHash,randomUUID}=require('node:crypto');
const Parent=require('./adminReceiptEmail.service');
const AppError=require('../utils/AppError');
const {encrypt}=require('../utils/tokenEncryption.util');
const {ADMIN_BOOKING_EMAIL_RESEND}=require('../policies/notificationEmail.policy');
const {renderCustomerEmail}=require('../templates/customerEmail');
function meta(value){try{return typeof value==='string'?JSON.parse(value)||{}:value||{}}catch{return {}}}
function fail(code){throw new AppError(code,{statusCode:409,errorCode:code})}
const ACTIVE=new Set(['OPEN','PENDING','CONFIRMED','DRIVER_ASSIGNED','ON_ROUTE','DRIVER_ARRIVED','PICKED_UP']);
class AdminBookingEmailService extends Parent {
  async context(number,conn=null,lock=false){
    const row=await this.repo.booking(conn,number,lock);
    if(!row)throw new AppError('BOOKING_NOT_FOUND',{statusCode:404,errorCode:'BOOKING_NOT_FOUND'});
    return {row,history:await this.repo.history(conn,row.id,{includeResends:true})};
  }
  isAccepted(delivery){
    return delivery.delivery_status==='DELIVERED'||Number(delivery.accepted_confirmed)>0||delivery.outcome==='ACCEPTED';
  }
  originalDelivery(history){
    return history.find(h=>h.type==='BOOKING_CREATED'&&h.event_name!==ADMIN_BOOKING_EMAIL_RESEND&&this.isAccepted(h));
  }
  eligibility(row,history){
    if(!ACTIVE.has(row.status))return 'RECEIPT_EMAIL_BOOKING_NOT_ACTIVE';
    const m=meta(row.metadata);
    if(m.adminBookingEmailResend?.approvedAt||m.adminReceiptEmail?.approvedAt)return 'RECEIPT_EMAIL_ALREADY_APPROVED';
    const original=history.filter(h=>h.type==='BOOKING_CREATED'&&h.event_name!==ADMIN_BOOKING_EMAIL_RESEND);
    // A new send is possible only after acceptance is known. Uncertain SMTP
    // outcomes remain in the existing review and recovery workflow.
    if(original.some(h=>!this.isAccepted(h)&&(Number(h.smtp_attempts)
      || Number(h.attempt_count)>0&&!['PERMANENT_INVALID_RECIPIENT','CONFIG_MISSING'].includes(h.last_error))))return 'RECEIPT_EMAIL_EXISTING_ATTEMPT';
    if(this.originalDelivery(history))return null;
    if(m.adminBookingConfirmationEmail?.approvedAt)return 'RECEIPT_EMAIL_ALREADY_APPROVED';
    if(history.filter(h=>this.isAccepted(h)||Number(h.smtp_attempts)).length>=2)return 'RECEIPT_EMAIL_LIMIT';
    return null;
  }
  state(row,history){
    const m=meta(row.metadata),prior=m.adminBookingEmailResend||m.adminBookingConfirmationEmail;
    const delivery=prior?history.find(h=>Number(h.id)===Number(prior.deliveryId)):this.originalDelivery(history)||history.find(h=>h.type==='BOOKING_CREATED');
    const reason=this.eligibility(row,history);
    return {eligible:!reason,reason,resend:Boolean(this.originalDelivery(history)),
      email:row.customer_email||'',locale:require('../templates/customerEmail').normalizeLocale(m.locale)||'en',
      configured:Boolean(this.notificationService.adapters.EMAIL?.isConfigured()),
      delivery:delivery?{deliveryId:delivery.id,status:delivery.delivery_status,outcome:delivery.outcome||null}:null,approvedAt:prior?.approvedAt||null};
  }
  async preview(number,input,actor){
    this.authorize(actor);const parsed=this.validate(input);const {row,history}=await this.context(number);
    const reason=this.eligibility(row,history);if(reason)fail(reason);
    const source=this.originalDelivery(history);
    return {...await this.document(row,parsed,source),preview:true,sent:false};
  }
  async document(row,input,source){
    const n={type:'BOOKING_CREATED',audience_role:'CUSTOMER',recipient_type:'GUEST_BOOKING',booking_number:row.booking_number,
      booking_metadata:{...meta(row.metadata),locale:input.locale},booking_status:row.status,booking_total_amount:row.total_amount,
      booking_currency:row.currency,booking_payment_status:row.payment_status,booking_payment_method:row.payment_method,
      booking_vehicle_type:row.vehicle_type_code,scheduled_pickup_at:row.scheduled_pickup_at,
      origin_address:row.origin_address,destination_address:row.destination_address,created_at:this.now().toISOString()};
    const output=renderCustomerEmail(n,{origin:this.notificationService.adapters.EMAIL?.customerWebOrigin});
    const previewHash=createHash('sha256').update(JSON.stringify({email:input.email,status:row.status,sourceDeliveryId:source?.id??null,output})).digest('hex');
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
      const source=this.originalDelivery(history);
      if(Boolean(source)!==(input.resend===true))fail('RECEIPT_EMAIL_PREVIEW_CHANGED');
      const doc=await this.document(row,parsed,source);if(!input.previewHash||input.previewHash!==doc.previewHash)fail('RECEIPT_EMAIL_PREVIEW_CHANGED');
      const key=createHash('sha256').update((source?ADMIN_BOOKING_EMAIL_RESEND:'ADMIN_BOOKING_CONFIRMATION_EMAIL')+':'+row.id).digest('hex');
      if(await this.notifications.findByIdempotencyKey(conn,key))fail('RECEIPT_EMAIL_ALREADY_APPROVED');
      id=await this.notifications.insertEmailOnly(conn,{recipientType:'GUEST_BOOKING',bookingId:row.id,audienceRole:'CUSTOMER',
        eventId:randomUUID(),eventName:source?ADMIN_BOOKING_EMAIL_RESEND:'ADMIN_BOOKING_EMAIL_APPROVED',idempotencyKey:key,notificationType:'BOOKING_CREATED',
        title:doc.subject,body:source?'Administrator-approved booking email resend':'Administrator-approved missing booking email',payload:{adminBookingConfirmation:true,locale:parsed.locale,
          approvedEmail:encrypt(JSON.stringify({to:parsed.email,subject:doc.subject,text:doc.text,html:doc.html}))}});
      const deliveryId=await this.notifications.insertDelivery(conn,{notificationId:id,channel:'EMAIL',deliveryStatus:'PENDING'});
      const record={approvedAt:this.now().toISOString(),actorUserId:actor.id,locale:parsed.locale,notificationId:id,deliveryId};
      if(source){
        record.sourceDeliveryId=source.id;
        await this.repo.approveBookingEmailResend(conn,row,record);
      }else{
        await this.repo.approveBookingEmail(conn,row,parsed.email,record);
      }
      await this.bookings.insertActivityLog(conn,row.id,{activityType:source?'BOOKING_EMAIL_RESEND_APPROVED':'BOOKING_EMAIL_APPROVED',actorUserId:actor.id,actorRole:actor.role,
        description:source?'Administrator approved booking email resend':'Administrator approved missing booking email',
        payload:{notificationId:id,deliveryId,sourceDeliveryId:source?.id??null,recipientMasked:parsed.email.replace(/^(.).*(@.*)$/,'$1***$2'),locale:parsed.locale}});
      await conn.commit();
    }catch(e){await conn.rollback();throw e}finally{conn.release()}
    try{await this.notificationService.processDeliveries(id)}catch{ /* The approval and delivery ledger remain authoritative. */ }
    return this.get(number,actor);
  }
}
module.exports=AdminBookingEmailService;
