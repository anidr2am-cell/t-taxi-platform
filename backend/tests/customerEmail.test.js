const test=require('node:test');const assert=require('node:assert/strict');const fs=require('fs');const path=require('path');
const {copy,CUSTOMER_TYPES,resolveEmailLocale,isCustomerEmail,bangkokDateTime,renderCustomerEmail}=require('../src/templates/customerEmail');
const {EmailNotificationAdapter}=require('../src/services/notificationDelivery.adapters');
const base={type:'TRIP_ENDED',audience_role:'CUSTOMER',recipient_type:'GUEST_BOOKING',booking_number:'QA_EMAIL',booking_metadata:{locale:'ko'},scheduled_pickup_at:'2026-10-15 23:30:00',booking_total_amount:'1000.00',origin_address:'QA origin',destination_address:'QA destination'};
test('email locale prioritizes booking, then member, then booking-screen locale, then English',()=>{
 assert.equal(resolveEmailLocale({...base,booking_metadata:'{"locale":"ja"}',recipient_locale:'ko',payload:{locale:'th'}}),'ja');
 assert.equal(resolveEmailLocale({...base,booking_metadata:{locale:'invalid'},recipient_locale:'zh-CN',payload:{locale:'th'}}),'zh');
 assert.equal(resolveEmailLocale({...base,booking_metadata:null,recipient_locale:null,payload:{locale:'th'}}),'th');
 assert.equal(resolveEmailLocale({recipient_type:'GUEST_BOOKING',booking_metadata:null}),'en');
 assert.equal(resolveEmailLocale({booking_metadata:'broken',recipient_locale:'invalid',payload:{locale:'invalid'}}),'en');
});
for(const locale of ['ko','en','th','ja','zh'])for(const type of CUSTOMER_TYPES){
 test(`customer email renders ${locale} ${type} with policies, Bangkok time, THB, no contacts`,()=>{
  const n={...base,type,booking_metadata:{locale},customerPhone:'PHONE_CANARY',customer_email:'EMAIL_CANARY',driverPhone:'DRIVER_PHONE_CANARY',customerContact:{messengerId:'ID_CANARY'},body:'UNTRUSTED_BODY',payload:{messengerId:'PAYLOAD_CANARY'}};
  const r=renderCustomerEmail(n,{googleReviewUrl:'https://g.page/r/test/review'});const t=copy[locale];
  assert.equal(r.subject,t.messages[type].subject);assert(r.text.includes(t.fare));assert(r.text.includes(t.cancel));assert(r.text.includes(t.payment));assert(r.text.includes(t.support));
  assert(r.text.includes('2026-10-15 23:30'));assert(r.text.includes('1,000 '+t.currency));assert(r.text.includes('lang='+locale));assert(r.html.includes('lang="'+locale+'"'));
  for(const secret of ['PHONE_CANARY','EMAIL_CANARY','DRIVER_PHONE_CANARY','ID_CANARY','PAYLOAD_CANARY','UNTRUSTED_BODY','SETTLEMENT_PENDING'])assert(!r.text.includes(secret)&&!r.html.includes(secret));
  if(type==='TRIP_COMPLETED')assert(!r.text.includes('g.page')&&!r.text.includes(t.google.split(':')[0])&&!r.text.includes(t.review.split('\n')[1]));
 });
}
for(const locale of ['ko','en','th','ja','zh'])test(`review copy matches PR152 and no gating: ${locale}`,()=>{
 const dart=fs.readFileSync(path.join(__dirname,'../../frontend/lib/l10n/app_localizations.dart'),'utf8');assert(dart.includes(JSON.stringify(copy[locale].review)));assert(dart.includes(JSON.stringify(copy[locale].google)));
 const first=renderCustomerEmail({...base,booking_metadata:{locale},rating:1,review_submitted:true},{googleReviewUrl:'https://g.page/r/test/review'});
 const high=renderCustomerEmail({...base,booking_metadata:{locale},rating:5},{googleReviewUrl:'https://g.page/r/test/review'});assert.deepEqual(first,high);
 assert(first.text.indexOf('https://g.page')<first.text.indexOf('/booking/lookup'));
 for(const googleReviewUrl of ['', 'http://unsafe.example','javascript:alert(1)'])assert(!renderCustomerEmail({...base,booking_metadata:{locale}},{googleReviewUrl}).text.includes('g.page'));
});
test('service datetime parser preserves SQL/mysql Date and converts explicit UTC across midnight',()=>{
 assert.equal(bangkokDateTime('2026-10-15 23:30:00'),'2026-10-15 23:30');
 assert.equal(bangkokDateTime(new Date('2026-10-15T23:30:00Z')),'2026-10-15 23:30');
 assert.equal(bangkokDateTime('2026-10-15T18:30:00Z'),'2026-10-16 01:30');
 assert.equal(bangkokDateTime('invalid'),null);
});
test('HTML escapes itinerary content and excludes credentials from Google links',()=>{
 const r=renderCustomerEmail({...base,origin_address:'<script>alert(1)</script>'},{googleReviewUrl:'https://user:secret@example.com/review'});assert(!r.html.includes('<script>'));assert(r.html.includes('&lt;script&gt;'));assert(!r.text.includes('secret'));
});
test('driver emails are disabled and admin emails retain legacy adapter template and never query review setting',async()=>{
 let settings=0,sends=0;const a=new EmailNotificationAdapter({smtp:{host:'smtp.example',fromEmail:'qa@example.com'},googleReviewUrlProvider:async()=>{settings++;return ''},transport:{async sendMail(){sends++}}});
 for(const audience_role of ['DRIVER','ADMIN']){const n={type:'TRIP_ENDED',audience_role,title:'Legacy',body:'Legacy body',recipient_email:'qa@example.com'};assert(!isCustomerEmail(n));assert.equal(a.buildMessage(n).subject,'Legacy');await a.send(n)}assert.equal(settings,0);assert.equal(sends,1);
});
test('customer send uses one SMTP call, optional Google setting failure does not change delivery',async()=>{
 let settings=0;const sent=[];const a=new EmailNotificationAdapter({smtp:{host:'smtp.example',fromEmail:'qa@example.com'},googleReviewUrlProvider:async()=>{settings++;throw Error('setting unavailable')},transport:{async sendMail(m){sent.push(m)}}});
 const result=await a.send({...base,recipient_email:'qa@example.com'});assert.equal(result.status,'DELIVERED');assert.equal(settings,1);assert.equal(sent.length,1);assert(sent[0].html);assert(!sent[0].text.includes('g.page'));
 const complete=await a.send({...base,type:'TRIP_COMPLETED',recipient_email:'qa@example.com'});assert.equal(complete.status,'SKIPPED');assert.equal(settings,1);
});
test('repository selects booking locale and amount without selecting contact fields',async()=>{
 const Repo=require('../src/repositories/notification.repository');let sql='';const repo=new Repo({async query(q){sql=q;return [[{id:1,payload:'{}'}]]}});await repo.findById(1);assert(sql.includes('b.metadata AS booking_metadata'));assert(sql.includes('b.total_amount AS booking_total_amount'));assert(!sql.includes('customer_phone'));assert(!sql.includes('driver_phone'));
});

test('every actual customer event type has a translated email in all five locales',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../src/services/notification.service.js'),'utf8');
 const types=[...source.matchAll(/addCustomer\(NOTIFICATION_TYPES\.([A-Z_]+)\)/g)].map(x=>x[1]);
 assert.equal(new Set(types).size,13);
 for(const type of types)for(const locale of Object.keys(copy))assert(copy[locale].messages[type].subject && (copy[locale].messages[type].body || type==='TRIP_ENDED'));
 assert(!isCustomerEmail({...base,audience_role:'DRIVER',recipient_user_role:'CUSTOMER'}));
});
