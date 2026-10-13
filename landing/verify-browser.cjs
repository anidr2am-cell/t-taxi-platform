const {chromium}=require('playwright'),fs=require('node:fs'),assert=require('node:assert/strict');
const base='http://159.89.192.55:3115',out='C:/TTaxi-screens/static-landing-ko-policy';fs.mkdirSync(out,{recursive:true});
(async()=>{const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const results={screens:[],requests:[],checks:[],performance:[]};
 for(const width of [375,1440]){
  const ctx=await browser.newContext({viewport:{width,height:width===375?812:1000}});const p=await ctx.newPage();
  p.on('response',r=>{if(r.url().includes('/api/'))results.requests.push({url:r.url(),method:r.request().method(),http:r.status(),backend:r.headers()['x-preview-backend']});});
  await p.goto(base);await p.getByRole('heading',{level:1}).waitFor();await p.getByText('최신 견적 API 확인 완료',{exact:false}).waitFor();
  assert.equal(await p.locator('#reviews').isVisible(),false);
  for(const keyword of ['수완나품','파타야','택시','1,000바트','추가요금 없음','24시간 상담']) {
   assert((await p.title()).includes(keyword));assert((await p.locator('meta[name="description"]').getAttribute('content')).includes(keyword));
  }
  assert.equal(await p.locator('#hero-price-amount').textContent(),await p.locator('[data-airport-row="BKK"][data-destination="PATTAYA"] [data-price="SEDAN"]').textContent());
  assert(!/\d|최대|정원|수용 없음/.test(await p.locator('.fleet-section').innerText()));
  assert.deepEqual(await p.locator('.vehicle h3').allTextContents(),['세단','SUV','밴']);
  for(const text of await p.locator('.eyebrow,.journey-top').allTextContents())assert(!/[A-Za-z]/.test(text));assert.equal(await p.locator('html').evaluate(e=>e.scrollWidth>innerWidth),false);
  await p.getByRole('button',{name:'거부',exact:true}).click();assert.equal(await p.evaluate(()=>localStorage.getItem('tride_analytics_consent')),'denied');
  await p.getByRole('button',{name:'돈므앙 DMK',exact:true}).click();await p.getByText('최신 견적 API 확인 완료',{exact:false}).waitFor();
  assert.equal(await p.locator('tr[data-airport-row="DMK"]:visible').count(),4);
  await p.getByRole('button',{name:'수완나품 BKK',exact:true}).click();await p.getByText('최신 견적 API 확인 완료',{exact:false}).waitFor();
  await p.evaluate(()=>window.scrollTo(0,0));await p.waitForTimeout(300);await p.screenshot({path:`${out}/landing-${width}-full.png`,fullPage:true});await p.screenshot({path:`${out}/landing-${width}-hero.png`});results.screens.push(`landing-${width}-full.png`,`landing-${width}-hero.png`);
  results.checks.push({width,overflow:false,hiddenReviews:true,quotesUpdated:true,cookieSharedKey:true});
  await ctx.close();
 }
 const ctx=await browser.newContext({viewport:{width:375,height:812}});const p=await ctx.newPage();
 // API failure: snapshot remains visible and the status cannot claim a live price.
 await p.route('**/api/v1/bookings/pricing/calculate',r=>r.fulfill({status:503,contentType:'application/json',body:'{"success":false}'}));
 await p.goto(base);await p.getByText('일부 최신 요금을 확인하지 못했어요.',{exact:false}).waitFor();assert.equal(await p.locator('[data-airport-row="BKK"][data-destination="PATTAYA"] [data-price="SEDAN"]').textContent(),'1,000');results.checks.push({quoteFailureFallback:true});await ctx.close();
 // Real service links, no booking is created.
 for(const [name,service] of [['공항 픽업','AIRPORT_PICKUP'],['공항 샌딩','AIRPORT_DROPOFF'],['도시간 이동','CITY_TRANSFER'],['골프 이동','GOLF_TRANSFER']]){
  const c=await browser.newContext({viewport:{width:375,height:812}});const q=await c.newPage();await q.goto(base);await q.getByRole('button',{name:'거부',exact:true}).click();
  await q.getByRole('link',{name:new RegExp(name)}).click();await q.waitForURL(base+'/booking?service='+service);
  await q.getByRole('button',{name:'Enable accessibility'}).dispatchEvent('click');await q.waitForTimeout(1200);
  await q.getByText(name,{exact:true}).first().waitFor({timeout:20000});assert.equal(await q.evaluate(()=>localStorage.getItem('tride_analytics_consent')),'denied');
  await q.screenshot({path:`${out}/booking-${service}-375.png`});results.checks.push({service,url:q.url(),flutterVisible:true});await c.close();
 }
 fs.writeFileSync(out+'/browser-verification.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results.checks));
}finally{await browser.close();}})().catch(e=>{console.error(e.stack);process.exit(1)});



