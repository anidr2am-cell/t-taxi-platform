const {test}=require('node:test');const assert=require('node:assert/strict');
const Service=require('../src/services/adminBookingEmail.service');const {emailPolicyError}=require('../src/policies/notificationEmail.policy');
const actor={id:77,role:'ADMIN'};
function harness({status='CONFIRMED',history=[],configured=true,outcome='ACCEPTED'}={}){
 const h={row:{id:1,booking_number:'TX209901010201',status,customer_email:null,total_amount:'1100',currency:'THB',payment_status:'PAID',payment_method:'ADMIN_COLLECTED',metadata:{locale:'ko'},vehicle_type_code:'SEDAN',scheduled_pickup_at:'2026-11-06 23:40:00',origin_address:'QA BKK',destination_address:'QA Hotel'},history:structuredClone(history),smtp:0,activities:[],notifications:[],queries:[]};let tail=Promise.resolve();
 const pool={async getConnection(){let release,snapshot;return {async beginTransaction(){const previous=tail;tail=new Promise(r=>{release=r});await previous;snapshot=structuredClone({row:h.row,history:h.history,notifications:h.notifications,activities:h.activities})},async commit(){release();release=null},async rollback(){Object.assign(h,snapshot);release?.();release=null},release(){},async query(sql,args){h.queries.push(sql);if(sql.includes("SET delivery_status='PENDING'")){const row=h.history.find(x=>x.id===args[0]);row.delivery_status='PENDING';row.last_error=null;}return [{}]}}}};
 const repo={async approveBookingEmail(_c,row,email,record){h.row.customer_email=email;h.row.metadata={...h.row.metadata,adminBookingConfirmationEmail:record};for(const x of h.history)if(x.type==='BOOKING_CREATED'&&x.id!==record.deliveryId&&!x.smtp_attempts)x.delivery_status='SKIPPED'},async decideDriverCollection(_c,row,record){h.row.payment_status=record.choice==='PAID'?'PAID':row.payment_status;h.row.metadata={...h.row.metadata,driverCollectionDecision:record}},async confirmPayment(_c,row,record){h.row.payment_status='PAID';h.row.metadata={...h.row.metadata,customerPaymentConfirmation:record}},async booking(){return structuredClone(h.row)},async history(){return structuredClone(h.history)},async approve(_c,row,email,record){h.row.customer_email=email;h.row.metadata={...h.row.metadata,adminReceiptEmail:record};for(const x of h.history)if(x.id!==record.deliveryId&&!x.smtp_attempts&&x.delivery_status!=='DELIVERED'){x.delivery_status='SKIPPED';x.last_error='EMAIL_POLICY_SUPERSEDED_BY_ADMIN_RECEIPT'}}};
 const notifications={async findByIdempotencyKey(_c,key){return h.notifications.find(x=>x.idempotencyKey===key)},async insertEmailOnly(_c,n){h.notifications.push({...n,id:101,channel:'EMAIL'});return 101},async insertDelivery(_c,d){h.history.push({id:201,notification_id:d.notificationId,type:'BOOKING_CREATED',delivery_status:'PENDING',smtp_attempts:0,attempt_count:0});return 201}};
 const booking={async insertActivityLog(_c,_id,a){h.activities.push(a)}};
 const notificationService={adapters:{EMAIL:{isConfigured:()=>configured,googleReviewUrlProvider:async()=>'',customerWebOrigin:'https://trider.taxi'}},async processDeliveries(id){const d=h.history.find(x=>x.notification_id===id);if(d.delivery_status!=='PENDING')return;h.smtp++;d.smtp_attempts=1;d.outcome=outcome;d.delivery_status=outcome==='ACCEPTED'?'DELIVERED':'FAILED';d.last_error=outcome==='UNKNOWN'?'PERMANENT_EMAIL_SEND_UNCERTAIN':null}};
 h.service=new Service(pool,repo,notifications,booking,notificationService,()=>new Date('2026-10-31T02:00:00Z'));return h;
}

const input={email:'qa@example.invalid',locale:'ko'};
for(const locale of ['ko','en','th','ja','zh'])test('booking preview is read-only and uses chosen language '+locale,async()=>{
 const h=harness(),d=await h.service.preview(h.row.booking_number,{...input,locale},actor);
 assert.equal(d.subject,require('../src/templates/customer-email.json')[locale].messages.BOOKING_CREATED.subject);
 assert(d.text.includes('2030')===false);assert(d.text.includes('23:40'));assert(d.text.includes('QA BKK'));assert(d.text.includes('1,100'));assert(d.text.includes('lang='+locale));
 assert.equal(h.smtp,0);assert.equal(h.row.customer_email,null);assert.equal(h.notifications.length,0);
});
test('missing-address mail repairs only receipt slot and freezes recipient/content with audit',async()=>{
 const h=harness({history:[{id:1,type:'BOOKING_CREATED',delivery_status:'FAILED',attempt_count:1,smtp_attempts:0,last_error:'PERMANENT_INVALID_RECIPIENT'}]});
 const old=structuredClone(h.row),p=await h.service.preview(h.row.booking_number,input,actor);
 await h.service.send(h.row.booking_number,{...input,previewHash:p.previewHash,confirmed:true},actor);
 assert.equal(h.smtp,1);assert.equal(h.row.customer_email,input.email);assert.equal(h.row.payment_status,old.payment_status);assert.equal(h.row.status,old.status);assert.equal(h.row.total_amount,old.total_amount);assert.equal(h.history[0].delivery_status,'SKIPPED');assert.equal(h.activities.length,1);
 const n=h.notifications[0];assert.equal(n.notificationType,'BOOKING_CREATED');assert.equal(n.channel,'EMAIL');assert.equal(n.payload.adminBookingConfirmation,true);
 const {decrypt}=require('../src/utils/tokenEncryption.util');const envelope=JSON.parse(decrypt(n.payload.approvedEmail));assert.equal(envelope.to,input.email);assert.equal(envelope.text,p.text);
 await assert.rejects(h.service.preview(h.row.booking_number,input,actor));assert.equal(h.smtp,1);
});
test('concurrent approval is one mail and one activity',async()=>{
 const h=harness(),p=await h.service.preview(h.row.booking_number,input,actor);const a={...input,previewHash:p.previewHash,confirmed:true};
 const r=await Promise.allSettled([h.service.send(h.row.booking_number,a,actor),h.service.send(h.row.booking_number,a,actor)]);assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.equal(h.smtp,1);assert.equal(h.activities.length,1);
});
for(const item of [{delivery_status:'DELIVERED'},{smtp_attempts:1,outcome:'UNKNOWN'},{smtp_attempts:1,outcome:'NOT_ACCEPTED'},{smtp_attempts:1,outcome:'SENDING'},{accepted_confirmed:1}])test('sent/uncertain SMTP is never bypassed '+JSON.stringify(item),async()=>{
 const h=harness({history:[{type:'BOOKING_CREATED',id:1,...item}]});await assert.rejects(h.service.preview(h.row.booking_number,input,actor));assert.equal(h.smtp,0);assert.equal(h.row.customer_email,null);
});
test('changed preview, unsupported trip state, configuration and role are protected',async()=>{
 for(const status of ['COMPLETED','SETTLEMENT_PENDING','CANCELLED','NO_SHOW']){const h=harness({status});await assert.rejects(h.service.preview(h.row.booking_number,input,actor));}
 const h=harness(),p=await h.service.preview(h.row.booking_number,input,actor);h.row.total_amount='1200';await assert.rejects(h.service.send(h.row.booking_number,{...input,previewHash:p.previewHash,confirmed:true},actor),/PREVIEW_CHANGED/);assert.equal(h.smtp,0);
 await assert.rejects(h.service.preview(h.row.booking_number,input,{role:'DRIVER'}),/FORBIDDEN/);
 const off=harness({configured:false});const v=await off.service.preview(off.row.booking_number,input,actor);await assert.rejects(off.service.send(off.row.booking_number,{...input,previewHash:v.previewHash,confirmed:true},actor),/UNAVAILABLE/);
});
test('worker with a stale original notification is blocked by current booking metadata',async()=>{
 const Repo=require('../src/repositories/notification.repository');let committed=false;
 const conn={async beginTransaction(){},async query(sql){if(sql.startsWith('SELECT id, metadata'))return [[{id:1,metadata:{adminBookingConfirmationEmail:{notificationId:99}}}]];throw Error('unexpected SQL')},async commit(){committed=true},async rollback(){},release(){}};
 const result=await new Repo({getConnection:async()=>conn}).claimCustomerEmail({id:1,type:'BOOKING_CREATED',booking_id:1},{id:10});assert.equal(result.allowed,false);assert.equal(result.error,'EMAIL_POLICY_SUPERSEDED_BY_ADMIN_BOOKING');assert(committed);
});
test('repository only changes contact/email metadata and old customer EMAIL delivery rows',async()=>{
 const Repo=require('../src/repositories/adminReceiptEmail.repository'),calls=[];await new Repo({}).approveBookingEmail({query:async(sql,args)=>{calls.push({sql,args});return [{}]}},{id:1},input.email,{actorUserId:77,deliveryId:9});
 assert.equal(calls.length,2);assert(calls[0].sql.includes("d.channel='EMAIL'"));assert(calls[0].sql.includes("n.type='BOOKING_CREATED'"));assert(calls[0].sql.includes("='CUSTOMER'"));assert(calls[0].sql.includes('NOT EXISTS'));assert(!/commission_|driver_id|payment_status|total_amount\s*=/.test(calls[1].sql));
});

test('approved booking mail uses frozen address and content with a mock transport only',async()=>{
 const h=harness(),p=await h.service.preview(h.row.booking_number,input,actor);await h.service.send(h.row.booking_number,{...input,confirmed:true,previewHash:p.previewHash},actor);
 const {EmailNotificationAdapter}=require('../src/services/notificationDelivery.adapters');const sent=[];
 const adapter=new EmailNotificationAdapter({smtp:{host:'smtp.example.invalid',fromEmail:'qa@example.invalid'},transport:{sendMail:async(m)=>{sent.push(m);return {messageId:'QA_ONLY',accepted:[m.to]}}}});
 const result=await adapter.send({type:'BOOKING_CREATED',audience_role:'CUSTOMER',recipient_type:'GUEST_BOOKING',recipient_email:'other@example.invalid',booking_number:h.row.booking_number,booking_total_amount:9999,payload:h.notifications[0].payload});
 assert.equal(result.status,'DELIVERED');assert.equal(sent.length,1);assert.equal(sent[0].to,input.email);assert.equal(sent[0].text,p.text);assert.equal(sent[0].subject,p.subject);
});
