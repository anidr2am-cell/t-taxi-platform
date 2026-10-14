'use strict';
const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const base=process.env.PREVIEW_ORIGIN,out=process.env.PREVIEW_SCREEN_DIR||'C:/TTaxi-screens/static-landing-stage2',locales=require('./locales.json'),snapshot=require('./snapshot.json');if(!base||new URL(base).protocol!=='https:'||new URL(base).origin!==base)throw Error('PREVIEW_ORIGIN must be an HTTPS origin');const backend=process.env.PREVIEW_BACKEND||'tride-landing-i18n-backend';const pickupRows=snapshot.rows.filter(r=>r.serviceTypeCode==='AIRPORT_PICKUP');fs.mkdirSync(out,{recursive:true});
(async()=>{const browser=await chromium.launch({channel:'chrome',headless:true}),result={base,landings:[],requests:[],routes:[],bookingClicks:[],checks:[]};
try{
 for(const [lang,t]of Object.entries(locales))for(const width of [375,1440]){
  const ctx=await browser.newContext({viewport:{width,height:width===375?812:1000},locale:'en-US'}),p=await ctx.newPage();let callCount=0;
  p.on('response',r=>{if(r.url().includes('/api/')){callCount++;result.requests.push({lang,width,url:r.url(),http:r.status(),method:r.request().method(),backend:r.headers()['x-preview-backend']});}});
  const route=lang==='ko'?'/':`/${lang}/`,r=await p.goto(base+route);assert.equal(r.status(),200);assert.equal(r.headers()['x-preview-backend'],backend);
  await p.waitForFunction(()=>document.querySelector('#fare-status').textContent.includes('2026')===false,{},{timeout:20000});
  assert.equal(await p.locator('html').getAttribute('lang'),lang);assert.equal(new URL(p.url()).pathname,route);assert.equal(await p.title(),t.title);
  assert.equal(await p.locator('link[rel="alternate"][hreflang]').count(),6);assert.equal(await p.locator('link[rel="canonical"]').getAttribute('href'),base+route);
  const schema=JSON.parse(await p.locator('script[type="application/ld+json"]').textContent());assert.equal(schema['@graph'][1].mainEntity.length,9);
  assert.equal(await p.locator('#reviews').isVisible(),false);assert.equal(await p.locator('html').evaluate(e=>e.scrollWidth>innerWidth),false,`${lang} ${width} overflow`);
  assert.equal(await p.locator('.fleet-section').count(),0);assert.equal(await p.locator('#how .steps li').count(),3);assert(await p.locator('.quiet').evaluate(e=>parseFloat(getComputedStyle(e).fontSize)>=16));assert.equal(await p.locator('.hero-copy > .eyebrow,.hero-copy > .kicker').count(),0);assert.equal(await p.locator('#hero-price-amount').textContent(),'1,000');
  assert.equal(await p.locator('.faq-list details').count(),9);assert.equal(await p.locator('[data-service]').count(),4);
  await p.locator('#cookie-deny').click();await p.locator('[data-airport="DMK"]').click();assert.equal(await p.locator('tr[data-airport-row="DMK"]:visible').count(),pickupRows.filter(r=>r.origin==='DMK').length);
  await p.locator('[data-airport="BKK"]').click();await p.evaluate(()=>scrollTo(0,0));await p.screenshot({path:`${out}/${lang}-${width}-full.png`,fullPage:true});await p.screenshot({path:`${out}/${lang}-${width}-hero.png`});
  assert.equal(callCount,1,'One landing API request only');result.landings.push({lang,width,http:200,overflow:false,apiCalls:callCount,htmlCache:r.headers()['cache-control'],title:await p.title(),description:await p.locator('meta[name="description"]').getAttribute('content')});
  if(width===375){await p.locator('[data-service="AIRPORT_PICKUP"]').click();await p.waitForURL(base+`/booking?service=AIRPORT_PICKUP&lang=${lang}`);let text='';for(let attempt=0;attempt<20;attempt++){const enable=p.getByRole('button',{name:'Enable accessibility'});if(await enable.count())await enable.dispatchEvent('click');text=(await p.locator('flt-semantics').allTextContents()).join(' ');if(text.trim().length>20)break;await p.waitForTimeout(1000);}assert(text.trim().length>20,'Flutter semantics rendered');assert(!text.includes('Route not found'));result.bookingClicks.push({lang,url:p.url(),visibleText:text.slice(0,300)});await p.screenshot({path:`${out}/booking-${lang}-375.png`});}
  await ctx.close();
 }
 const app=fs.readFileSync(path.join(__dirname,'../frontend/build/web/index.html')),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
 const paths=['/booking','/booking?service=AIRPORT_PICKUP','/booking/contact-connect','/booking/lookup','/my-bookings','/account','/profile/complete','/privacy-policy','/support','/admin','/driver','/driver/login','/driver/apply','/driver/application-status','/driver/home','/driver/jobs','/auth/kakao/callback','/auth/line/callback'];
 for(const route of paths){const r=await fetch(base+route),bytes=Buffer.from(await r.arrayBuffer());assert.equal(r.status,200);assert.equal(hash(bytes),hash(app));result.routes.push({route,http:200,flutterIndexIdentical:true});}
 for(const route of ['/blog/','/blog/suvarnabhumi-to-bangkok-city','/manifest.json','/manifest-driver.json','/flutter_service_worker.js','/api/v1/health']){const r=await fetch(base+route);assert.equal(r.status,200);result.routes.push({route,http:200});}
 const download=await fetch(base+'/downloads/',{redirect:'manual'});assert.equal(download.status,302);result.routes.push({route:'/downloads/',http:302,location:download.headers.get('location')});
 for(const name of ['sitemap.xml','sitemap-landing.xml','sitemap-blog.xml','robots.txt']){const r=await fetch(base+'/'+name),text=await r.text();assert.equal(r.status,200);if(name==='sitemap.xml'){assert(text.includes('<sitemapindex'));for(const child of ['sitemap-landing.xml','sitemap-blog.xml'])assert(text.includes(`<loc>${base}/${child}</loc>`));}else if(name==='sitemap-landing.xml'){for(const lang of Object.keys(locales))assert(text.includes(`<loc>${base}${lang==='ko'?'/':`/${lang}/`}</loc>`));assert.equal((text.match(/<lastmod>/g)||[]).length,5);}else if(name==='sitemap-blog.xml'){assert(text.includes('/blog/'));assert(text.includes('<lastmod>'));}else for(const prefix of ['/admin','/driver','/api'])assert(text.includes('Disallow: '+prefix));result.checks.push({name,http:200});}
 const c=await browser.newContext({javaScriptEnabled:false}),p=await c.newPage();for(const lang of Object.keys(locales)){await p.goto(base+(lang==='ko'?'/':`/${lang}/`));assert.equal(await p.locator('#hero-price-amount').textContent(),'1,000');assert.equal(await p.locator('tbody tr').count(),pickupRows.length);assert.equal(await p.locator('.faq-list details').count(),9);}await c.close();result.checks.push({serverRenderedWithoutJavaScript:5});
 for(const scenario of ['invalid-price','new-route']){
  const mock=structuredClone({rows:snapshot.rows,channels:snapshot.channels});
  if(scenario==='invalid-price')mock.rows.find(r=>r.serviceTypeCode==='AIRPORT_PICKUP').prices.SEDAN=null;
  else mock.rows.push({...mock.rows.find(r=>r.serviceTypeCode==='AIRPORT_PICKUP'&&r.destination==='AYUTTHAYA'),origin:'CNX',originLabel:'Chiang Mai'});
  const c=await browser.newContext(),p=await c.newPage();await p.route('**/api/v1/public/landing-data',r=>r.fulfill({contentType:'application/json',body:JSON.stringify({success:true,data:mock})}));await p.goto(base);
  if(scenario==='invalid-price'){await p.getByText(locales.ko.fares[9],{exact:false}).waitFor();assert.equal(await p.locator('#hero-price-amount').textContent(),'1,000');}
  else{await p.locator('[data-airport="CNX"]').waitFor();await p.locator('[data-airport="CNX"]').click();assert.equal(await p.locator('tr[data-airport-row="CNX"]:visible').count(),1);}
  result.checks.push({scenario,controlledMock:true,pass:true});await c.close();
 }
 const fallback=await browser.newContext(),f=await fallback.newPage();await f.route('**/api/v1/public/landing-data',r=>r.fulfill({status:503,contentType:'application/json',body:'{"success":false}'}));await f.goto(base);await f.getByText(locales.ko.fares[9],{exact:false}).waitFor();assert.equal(await f.locator('#hero-price-amount').textContent(),'1,000');await fallback.close();result.checks.push({apiFailureRetainsSnapshot:true});
}finally{await browser.close();fs.writeFileSync(out+'/verification.json',JSON.stringify(result,null,2));}
console.log(JSON.stringify({landings:result.landings.length,routes:result.routes.length,bookingClicks:result.bookingClicks.length,checks:result.checks}));
})().catch(e=>{console.error(e.stack);process.exit(1)});
