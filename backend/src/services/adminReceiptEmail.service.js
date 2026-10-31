const {createHash,randomUUID}=require('node:crypto');
const {withReceiptPdf,PDF_TEMPLATE_VERSION}=require('../templates/customerReceiptPdf');
const AppError=require('../utils/AppError');
const {encrypt}=require('../utils/tokenEncryption.util');
const {renderCustomerEmail,normalizeLocale}=require('../templates/customerEmail');
const {customerEmailSlot,CUSTOMER_EMAIL_LIMIT}=require('../policies/notificationEmail.policy');
function meta(value){try{return typeof value==='string'?JSON.parse(value)||{}:value||{}}catch{return {}}}
function fail(code,status=409){throw new AppError(code,{statusCode:status,errorCode:code})}
function mask(email){const [local,domain]=String(email||'').split('@');return domain?local.slice(0,1)+'***@'+domain:''}
class AdminReceiptEmailService {
  constructor(pool,repo,notifications,bookings,notificationService,now=()=>new Date()) {
    Object.assign(this,{pool,repo,notifications,bookings,notificationService,now});
  }
  authorize(actor){if(!['ADMIN','SUPER_ADMIN'].includes(actor?.role))fail('FORBIDDEN',403)}
  validate(input){
    const email=String(input.email||'').trim();const locale=normalizeLocale(input.locale);
    if(email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))fail('RECEIPT_EMAIL_INVALID',400);
    if(!locale)fail('RECEIPT_EMAIL_LOCALE_REQUIRED',400);
    return {email,locale};
  }
  eligibility(row,history){
    if(!['SETTLEMENT_PENDING','COMPLETED'].includes(row.status))return 'RECEIPT_EMAIL_TRIP_NOT_ENDED';
    if(meta(row.metadata).adminReceiptEmail?.approvedAt)return 'RECEIPT_EMAIL_ALREADY_APPROVED';
    const safeNoSmtp=(h)=>!Number(h.smtp_attempts)&&(!Number(h.attempt_count)
      || ['PERMANENT_INVALID_RECIPIENT','CONFIG_MISSING'].includes(h.last_error)
      || String(h.last_error||'').startsWith('EMAIL_POLICY_'));
    if(history.some(h=>h.type==='BOOKING_CREATED' && h.delivery_status!=='DELIVERED' && !['ACCEPTED','NOT_ACCEPTED'].includes(h.outcome) && !safeNoSmtp(h))) return 'RECEIPT_EMAIL_EXISTING_ATTEMPT';
    if(history.some(h=>customerEmailSlot(h.type)==='TERMINAL' && (h.delivery_status==='DELIVERED'
      || Number(h.accepted_confirmed)||!safeNoSmtp(h))))return 'RECEIPT_EMAIL_EXISTING_ATTEMPT';
    if(history.filter(h=>h.delivery_status==='DELIVERED'||Number(h.accepted_confirmed)
      || Number(h.smtp_attempts)||String(h.last_error||'').startsWith('PERMANENT_EMAIL_')).length>=CUSTOMER_EMAIL_LIMIT)
      return 'RECEIPT_EMAIL_LIMIT';
    return null;
  }
  async context(number,conn=null,lock=false){
    const row=await this.repo.booking(conn,number,lock);if(!row)fail('BOOKING_NOT_FOUND',404);
    return {row,history:await this.repo.history(conn,row.id)};
  }
  state(row,history){
    const m=meta(row.metadata);const prior=m.adminReceiptEmail;
    const delivery=prior?history.find(h=>Number(h.id)===Number(prior.deliveryId)):history.find(h=>customerEmailSlot(h.type)==='TERMINAL');
    const reason=this.eligibility(row,history);
    return {payment:{status:row.payment_status,amount:row.total_amount==null?null:Number(row.total_amount),currency:row.currency,canConfirm:['SETTLEMENT_PENDING','COMPLETED'].includes(row.status)&&['UNPAID','PENDING'].includes(row.payment_status)&&row.total_amount!=null&&Number.isFinite(Number(row.total_amount))&&Number(row.total_amount)>=0&&row.currency==='THB',confirmation:m.customerPaymentConfirmation||null},eligible:!reason,reason,email:row.customer_email||'',locale:normalizeLocale(m.locale)||'en',
      configured:Boolean(this.notificationService.adapters.EMAIL?.isConfigured()),
      delivery:delivery?{deliveryId:delivery.id,status:delivery.delivery_status,outcome:delivery.outcome||null}:null,
      approvedAt:prior?.approvedAt||null};
  }
  async get(number,actor){this.authorize(actor);const {row,history}=await this.context(number);return this.state(row,history)}
  async confirmPayment(number,input,actor){
    this.authorize(actor);
    const reason=String(input.reason||'').trim();
    if(input.confirmed!==true||!reason||reason.length>500)fail('CUSTOMER_PAYMENT_CONFIRM_REQUIRED',400);
    const conn=await this.pool.getConnection();
    try{
      await conn.beginTransaction();
      const row=await this.repo.booking(conn,number,true);if(!row)fail('BOOKING_NOT_FOUND',404);
      if(!['SETTLEMENT_PENDING','COMPLETED'].includes(row.status))fail('CUSTOMER_PAYMENT_TRIP_NOT_ENDED');
      if(row.payment_status!=='PAID'&&!['UNPAID','PENDING'].includes(row.payment_status))fail('CUSTOMER_PAYMENT_STATE_BLOCKED');
      const amount=row.total_amount==null?NaN:Number(row.total_amount);
      if(!Number.isFinite(amount)||amount<0||row.currency!=='THB'||typeof input.expectedAmount!=='number'
        ||amount!==input.expectedAmount||input.expectedCurrency!==row.currency)fail('CUSTOMER_PAYMENT_CHANGED');
      if(row.payment_status!=='PAID'){
        const record={confirmedAt:this.now().toISOString(),confirmedByUserId:actor.id,
          previousStatus:row.payment_status,amount,currency:row.currency,reason};
        await this.repo.confirmPayment(conn,row,record,actor.id);
        await this.bookings.insertActivityLog(conn,row.id,{activityType:'CUSTOMER_PAYMENT_CONFIRMED',actorUserId:actor.id,
          actorRole:actor.role,description:'Administrator confirmed customer payment; no email sent',payload:record});
      }
      await conn.commit();
    }catch(e){await conn.rollback();throw e}finally{conn.release()}
    // Payment acknowledgement never sends email or changes commission/assignments.
    return this.get(number,actor);
  }
  async document(row,input,googleOverride){
    const adapter=this.notificationService.adapters.EMAIL;
    let google=googleOverride;
    if(google===undefined){google='';try{google=await adapter.googleReviewUrlProvider()}catch{}}
    const n={type:'TRIP_ENDED',audience_role:'CUSTOMER',recipient_type:'GUEST_BOOKING',booking_number:row.booking_number,
      booking_metadata:row.metadata,booking_status:row.status,booking_total_amount:row.total_amount,
      booking_currency:row.currency,booking_payment_status:row.payment_status,booking_payment_method:row.payment_method,
      booking_vehicle_type:row.vehicle_type_code,scheduled_pickup_at:row.scheduled_pickup_at,
      origin_address:row.origin_address,destination_address:row.destination_address,
      payload:{adminReceipt:true,locale:input.locale},created_at:this.now().toISOString()};
    const options={origin:adapter.customerWebOrigin,googleReviewUrl:google};
    const output=await withReceiptPdf(renderCustomerEmail(n,options));
    // Stable across clock ticks; any amount, status, route, language, setting or template change invalidates approval.
    const stable=renderCustomerEmail({...n,created_at:'2000-01-01T00:00:00.000Z'},options);
    const previewHash=createHash('sha256').update(JSON.stringify({email:input.email,subject:stable.subject,text:stable.text,pdfTemplate:PDF_TEMPLATE_VERSION})).digest('hex');
    return {...output,previewHash,email:input.email};
  }
  async preview(number,input,actor){
    this.authorize(actor);const parsed=this.validate(input);const {row,history}=await this.context(number);
    const reason=this.eligibility(row,history);if(reason)fail(reason);
    return {...await this.document(row,parsed),preview:true,sent:false};
  }
  async send(number,input,actor){
    this.authorize(actor);const parsed=this.validate(input);if(input.confirmed!==true)fail('RECEIPT_EMAIL_CONFIRM_REQUIRED',400);
    if(!this.notificationService.adapters.EMAIL?.isConfigured())fail('RECEIPT_EMAIL_UNAVAILABLE');
    let google='';try{google=await this.notificationService.adapters.EMAIL.googleReviewUrlProvider()}catch{}
    const conn=await this.pool.getConnection();let id;
    try{
      await conn.beginTransaction();
      const {row,history}=await this.context(number,conn,true);
      const reason=this.eligibility(row,history);if(reason)fail(reason);
      const doc=await this.document(row,parsed,google);if(!input.previewHash||input.previewHash!==doc.previewHash)fail('RECEIPT_EMAIL_PREVIEW_CHANGED');
      const key=createHash('sha256').update('ADMIN_RECEIPT_EMAIL:'+row.id).digest('hex');
      if(await this.notifications.findByIdempotencyKey(conn,key))fail('RECEIPT_EMAIL_ALREADY_APPROVED');
      id=await this.notifications.insertEmailOnly(conn,{recipientType:'GUEST_BOOKING',bookingId:row.id,audienceRole:'CUSTOMER',
        eventId:randomUUID(),eventName:'ADMIN_RECEIPT_EMAIL_APPROVED',idempotencyKey:key,notificationType:'TRIP_ENDED',
        title:doc.subject,body:'Administrator-approved trip document',payload:{adminReceipt:true,locale:parsed.locale,approvedEmail:encrypt(JSON.stringify({to:parsed.email,subject:doc.subject,text:doc.text,html:doc.html,attachments:doc.attachments}))}});
      const deliveryId=await this.notifications.insertDelivery(conn,{notificationId:id,channel:'EMAIL',deliveryStatus:'PENDING'});
      // Supersede old missing-address email rows before the entered address becomes visible.
      await this.repo.approve(conn,row,parsed.email,{approvedAt:this.now().toISOString(),actorUserId:actor.id,
        locale:parsed.locale,notificationId:id,deliveryId});
      await this.bookings.insertActivityLog(conn,row.id,{activityType:'RECEIPT_EMAIL_APPROVED',actorUserId:actor.id,
        actorRole:actor.role,description:'Administrator approved first trip document email',
        payload:{notificationId:id,deliveryId,recipientMasked:mask(parsed.email),locale:parsed.locale}});
      await conn.commit();
    }catch(e){await conn.rollback();throw e}finally{conn.release()}
    // Uses the existing booking-row email slot lock, immutable envelope and SMTP outcome ledger.
    // A racing worker can claim the same delivery, but can never send it twice.
    try{await this.notificationService.processDeliveries(id)}catch{ /* Keep approval; never auto-retry an uncertain response. */ }
    return this.get(number,actor);
  }
}
module.exports=AdminReceiptEmailService;
