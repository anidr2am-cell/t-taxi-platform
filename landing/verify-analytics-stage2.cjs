'use strict';
const {chromium}=require('playwright'),fs=require('node:fs'),assert=require('node:assert/strict');
const base=process.env.PREVIEW_ORIGIN||'https://exports-usb-handy-topic.trycloudflare.com',out='C:/TTaxi-screens/static-landing-stage2';
(async()=>{const b=await chromium.launch({channel:'chrome',headless:true}),ctx=await b.newContext(),p=await ctx.newPage(),events=[],requests=[];
try{
 await p.exposeFunction('recordGtag',args=>events.push(args));
 await p.route(base+'/',async route=>{const r=await route.fetch();let html=await r.text();html=html.replace('"analyticsEnabled":false,"measurementId":""','"analyticsEnabled":true,"measurementId":"G-1BRG6R9LWY"');await route.fulfill({response:r,body:html});});
 await p.route('https://www.googletagmanager.com/**',r=>{requests.push(r.request().url());return r.fulfill({contentType:'application/javascript',body:'window.gtag=function(){window.recordGtag(Array.from(arguments));};window.__mockGaLoaded=true;'});});
 await p.goto(base+'/?utm_source=qa'); // The base interception below also covers the query.
 if(!(await p.locator('#landing-data').textContent()).includes('"analyticsEnabled":true'))await p.goto(base+'/');
 await p.waitForTimeout(500);assert.equal(requests.length,0);assert.equal(await p.evaluate(()=>localStorage.getItem('tride_analytics_consent')),null);
 await p.locator('#cookie-deny').click();await p.locator('[data-airport="DMK"]').click();assert.equal(requests.length,0);assert.equal(events.length,0);
 await p.locator('#consent-settings').click();await p.locator('#cookie-accept').click();await p.waitForFunction(()=>window.__mockGaLoaded===true);assert.equal(requests.length,1);
 await p.evaluate(()=>document.addEventListener('click',e=>{if(e.target.closest('a[data-service],a[data-channel]'))e.preventDefault();}));
 await p.locator('[data-service="AIRPORT_PICKUP"]').click();await p.locator('[data-airport="BKK"]').click();await p.locator('[data-channel]').first().click();
 await p.locator('#language-select').selectOption('en');await p.waitForURL(base+'/en/');
 const names=events.filter(e=>e[0]==='event').map(e=>e[1]);for(const name of ['landing_service_click','landing_fare_origin_change','landing_support_click','landing_language_change'])assert(names.includes(name),name);
 assert.equal(await p.evaluate(()=>localStorage.getItem('tride_analytics_consent')),'granted');
 await p.goto(base+'/');await p.locator('#consent-settings').click();await p.locator('#cookie-deny').click();assert.equal(await p.evaluate(()=>window['ga-disable-G-1BRG6R9LWY']),true);const count=events.filter(e=>e[0]==='event').length;await p.locator('[data-airport="DMK"]').click();await p.waitForTimeout(100);assert.equal(events.filter(e=>e[0]==='event').length,count);
 const result={pass:true,googleRequestsBeforeConsent:0,googleRequestsAfterDenial:0,controlledMock:true,events:names,sharedStorageKey:'tride_analytics_consent',requests};fs.writeFileSync(out+'/analytics-consent.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}finally{await b.close();}})().catch(e=>{console.error(e.stack);process.exit(1)});
