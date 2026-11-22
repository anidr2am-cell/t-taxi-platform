// Synthetic isolated preview only. No booking submission or customer messages.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||require('path').resolve(__dirname,'../../../backend/node_modules/playwright'));
const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const base=process.env.PREVIEW_URL,out=process.env.QA_OUTPUT,fixture=require('../customer-booking-ux/booking-state.json');
async function semantics(p){await p.locator('flt-semantics-placeholder').dispatchEvent('click');await p.waitForFunction(()=>/[1-5]\/5/.test(document.body.innerText));await p.waitForTimeout(450);}
async function stored(p){return p.evaluate(()=>{const v=JSON.parse(localStorage.getItem('flutter.booking_wizard_draft_v2'));return (typeof v==='string'?JSON.parse(v):v).state;});}
async function load(p,state){await p.goto(base+'/en/');await p.evaluate(state=>{localStorage.clear();sessionStorage.clear();localStorage.setItem('tride_analytics_consent','denied');localStorage.setItem('flutter.booking_wizard_draft_v2',JSON.stringify(JSON.stringify({version:3,savedAt:new Date().toISOString(),expiresAt:new Date(Date.now()+14400000).toISOString(),state})));},state);await p.goto(base+'/booking?lang=en');await semantics(p);}
(async()=>{
 assert(base?.startsWith('https://')&&new URL(base).hostname!=='trider.taxi'&&out);
 assert.equal((await fetch(base)).headers.get('x-preview-backend'),'booking-flow-refinement-20261122');fs.mkdirSync(out,{recursive:true});
 const b=await chromium.launch({headless:true,channel:'chrome'}),results=[];
 async function run(name,fn){const c=await b.newContext({viewport:{width:390,height:844}}),p=await c.newPage();await c.route('**/*',r=>{const u=new URL(r.request().url());if(!['GET','HEAD'].includes(r.request().method())&&(u.origin!==new URL(base).origin||/\/bookings$|confirm-sent|send|payment/.test(u.pathname)))return r.abort();return r.continue();});try{await fn(p,c);results.push({name,ok:true});console.log('PASS',name);}catch(e){results.push({name,ok:false,error:e.message});await p.screenshot({path:path.join(out,'FAILED-'+name+'.png')}).catch(()=>{});console.log('FAIL',name,e.message);}finally{await c.close();}}
 try{
 await run('pending-detail-route-skip-and-edit-preserves',async(p,c)=>{
  let release;const pending=new Promise(r=>release=r);await c.route('**/places/details?**',async r=>{await pending;return r.fulfill({json:{success:true,data:{name:'QA Hotel',formattedAddress:'QA Pattaya',lat:12.936,lng:100.886}}});});
  await p.goto(base+'/en/');await p.click('#cookie-deny');await p.selectOption('#airport-from','BKK');await p.fill('#quick-to','QA');await p.locator('#results-to button').first().click();
  assert(await p.locator('.primary-action').isDisabled());assert(!(await p.locator('#error-to').isVisible()));await p.screenshot({path:out+'/detail-pending.png'});release();
  await p.waitForFunction(()=>!!JSON.parse(sessionStorage.getItem('tride_landing_form_v1')).endpoints.to);await p.locator('.primary-action').click();await p.waitForURL('**/booking?**');await semantics(p);assert((await p.locator('body').innerText()).includes('2/5'));assert(!(await p.locator('body').innerText()).includes('1/5'));await p.screenshot({path:out+'/confirmed-route-schedule.png'});
  // Populate only a local synthetic draft to test edit/back preservation.
  await load(p,{...fixture,step:1,adults:2,luggage20:2});
  await p.getByRole('button',{name:'Edit route',exact:true}).click();await p.waitForFunction(()=>document.body.innerText.includes('1/5'));assert.equal((await stored(p)).pickupTime,'10:30');assert.equal((await stored(p)).adults,2);assert.equal((await stored(p)).luggage20,2);
  await p.getByRole('button').last().click();await p.waitForFunction(()=>document.body.innerText.includes('2/5'));await p.reload();await semantics(p);assert((await p.locator('body').innerText()).includes('2/5'));assert.equal((await stored(p)).pickupDate,'2026-12-10');
 });
 await run('manual-without-flight-and-invalid-time',async(p)=>{
  await load(p,{...fixture,step:1,flightNumber:'',flightDate:''});await p.getByRole('radio',{name:'Enter Thailand arrival date and time',exact:true}).click();assert.equal(await p.getByRole('button',{name:'Look up',exact:true}).count(),0);
  await p.getByText('Type the time',{exact:true}).click();const input=p.getByRole('textbox').last();await input.fill('99:99');assert(await p.getByRole('button').last().isDisabled());await input.fill('22:10');await p.waitForTimeout(500);assert.equal((await stored(p)).pickupTime,'22:10');await p.screenshot({path:out+'/manual-time.png'});await p.getByRole('button').last().click();await p.waitForFunction(()=>document.body.innerText.includes('3/5'));assert.equal((await stored(p)).flightNumber,'');
 });
 await run('flight-midnight-existing-50-minute-rule',async(p)=>{
  await load(p,{...fixture,step:1,flightNumber:'QA101',flightDate:'2026-12-10'});await p.getByRole('button',{name:'Look up',exact:true}).click();const buffer=p.getByRole('button').filter({hasText:/50/}).first();await buffer.waitFor();await buffer.click();await p.waitForTimeout(500);const s=await stored(p);assert.equal(s.pickupDate,'2026-12-11');assert.equal(s.pickupTime,'01:30');await p.screenshot({path:out+'/flight-midnight.png'});
 });
 for(const failure of ['empty','error','delay'])await run('flight-'+failure+'-manual-fallback',async(p,c)=>{
  await c.route('**/public/flights/search?**',async r=>{if(failure==='delay')await new Promise(resolve=>setTimeout(resolve,2500));return r.fulfill({status:failure==='error'?503:200,json:failure==='error'?{success:false,message:'RAW QA ERROR'}:{success:true,data:{matches:[]}}}).catch(()=>{});});
  await load(p,{...fixture,step:1,flightNumber:'QA101',flightDate:'2026-12-10'});await p.getByRole('button',{name:'Look up',exact:true}).click();const manual=p.getByRole('button',{name:'Enter Thailand arrival date and time',exact:true});await manual.last().waitFor();await manual.last().click();assert(!(await p.locator('body').innerText()).includes('RAW QA'));assert.equal((await stored(p)).flightNumber,'QA101');await p.getByRole('button').last().click();await p.waitForFunction(()=>document.body.innerText.includes('3/5'));
 });
 await run('landing-stale-search-retry-and-invalidation',async(p,c)=>{
  await p.goto(base+'/en/');await p.click('#cookie-deny');await p.locator('[data-service="CITY_TRANSFER"]').click();let release;const pending=new Promise(r=>release=r);
  await c.route('**/places/autocomplete?**',async r=>{const q=new URL(r.request().url()).searchParams.get('input');if(q==='Older')await pending;return r.fulfill({json:{success:true,data:{predictions:[{placeId:q,mainText:q,secondaryText:'QA'}]}}});});
  await p.fill('#quick-from','Older');await p.waitForTimeout(500);await p.fill('#quick-from','Newer');await p.locator('#results-from button').filter({hasText:'Newer'}).waitFor();release();await p.waitForTimeout(250);assert(!(await p.locator('#results-from').innerText()).includes('Older'));await p.locator('#results-from button').first().click();await p.waitForFunction(()=>!!JSON.parse(sessionStorage.getItem('tride_landing_form_v1')).endpoints.from);await p.fill('#quick-from','Changed');await p.waitForTimeout(400);assert(!JSON.parse(await p.evaluate(()=>sessionStorage.getItem('tride_landing_form_v1'))).endpoints.from);
  await c.unroute('**/places/autocomplete?**');await c.route('**/places/autocomplete?**',r=>r.fulfill({status:503,json:{success:false,message:'RAW QA ERROR'}}));await p.fill('#quick-from','Failed');await p.locator('#retry-from').waitFor();assert(!(await p.locator('#quick-status').innerText()).includes('RAW QA'));await c.unroute('**/places/autocomplete?**');await p.click('#retry-from');await p.locator('#results-from button').first().waitFor();await p.screenshot({path:out+'/search-retry.png'});
 });
 }finally{await b.close();fs.writeFileSync(out+'/refinement-results.json',JSON.stringify({realDevicesTested:false,results},null,2));}if(results.some(r=>!r.ok))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});

