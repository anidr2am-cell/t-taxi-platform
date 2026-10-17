'use strict';
(() => {
 const data=JSON.parse(document.querySelector('#landing-data').textContent);
 const key='tride_analytics_consent',banner=document.querySelector('#cookie-banner');
 const read=()=>{try{return localStorage.getItem(key);}catch{return null;}};
 let initialized=false;
 function analytics(){
  if(initialized||read()!=='granted'||!data.analyticsEnabled||!/^G-[A-Z0-9]+$/.test(data.measurementId))return;
  initialized=true;window['ga-disable-'+data.measurementId]=false;window.dataLayer=window.dataLayer||[];window.gtag=window.gtag||function(){window.dataLayer.push(arguments);};
  window.gtag('consent','default',{analytics_storage:'granted',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'});
  window.gtag('js',new Date());window.gtag('config',data.measurementId,{send_page_view:true,anonymize_ip:true,page_location:location.origin+location.pathname,page_referrer:document.referrer?new URL(document.referrer).origin:''});
  const script=document.createElement('script');script.async=true;script.src='https://www.googletagmanager.com/gtag/js?id='+encodeURIComponent(data.measurementId);document.head.append(script);
 }
 function event(name,details){if(read()!=='granted')return;analytics();if(initialized)window.gtag('event',name,{language:data.lang,...details});}
 function save(value){try{localStorage.setItem(key,value);if(value==='denied'){localStorage.removeItem('tride_marketing_first_touch');localStorage.removeItem('tride_marketing_last_touch');}}catch{}banner.hidden=true;window['ga-disable-'+data.measurementId]=value!=='granted';
  if(value==='granted'){captureAttribution();if(initialized)window.gtag('consent','update',{analytics_storage:'granted'});analytics();}else if(initialized)window.gtag('consent','update',{analytics_storage:'denied'});
 }
  function captureAttribution(){
  const params=new URLSearchParams(location.search),touch={schema_version:2,landing_page:location.pathname,captured_at:new Date().toISOString(),expires_at:new Date(Date.now()+90*86400000).toISOString()};
  let hasUtm=false;for(const name of ['source','medium','campaign','content','term']){const v=params.get('utm_'+name);if(v&&/^[a-zA-Z0-9._-]{1,150}$/.test(v)&&!/^\+?[0-9\s()-]{7,20}$/.test(v)){touch[name]=v;hasUtm=true;}}
  try{const host=document.referrer?new URL(document.referrer).hostname:null;if(host&&/^[a-z0-9.-]{1,255}$/.test(host))touch.referrer_host=host;
   const old=JSON.parse(localStorage.getItem('tride_marketing_first_touch')||'null');if(!old||Date.parse(old.expires_at)<Date.now())localStorage.setItem('tride_marketing_first_touch',JSON.stringify(touch));if(hasUtm)localStorage.setItem('tride_marketing_last_touch',JSON.stringify(touch));
  }catch{}
 }

 document.querySelector('#cookie-accept').addEventListener('click',()=>save('granted'));
 document.querySelector('#cookie-deny').addEventListener('click',()=>save('denied'));
 document.querySelector('#consent-settings').addEventListener('click',()=>banner.hidden=false);
 banner.hidden=['granted','denied'].includes(read());if(read()==='granted'){captureAttribution();analytics();}
 document.querySelectorAll('[data-service]').forEach(a=>a.addEventListener('click',()=>{const url=new URL(a.href);url.searchParams.set('entry',crypto.randomUUID());a.href=url.href;event('landing_service_click',{service_type:a.dataset.service});}));
 document.querySelector('#language-select').addEventListener('change',e=>{const lang=e.target.value;if(!['ko','en','th','ja','zh'].includes(lang))return;event('landing_language_change',{destination_language:lang});location.href=lang==='ko'?'/':`/${lang}/`;});
 document.querySelector('#support-actions').addEventListener('click',e=>{const a=e.target.closest('[data-channel]');if(a)event('landing_support_click',{channel:a.dataset.channel});});
 document.querySelector('.airport-tabs').addEventListener('click',e=>{
  const button=e.target.closest('[data-airport]');if(!button)return;
  const airport=button.dataset.airport;document.querySelectorAll('[data-airport]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
  document.querySelectorAll('[data-airport-row]').forEach(r=>r.hidden=r.dataset.airportRow!==airport);event('landing_fare_origin_change',{airport});
 });
 const allowedContact=raw=>{try{const u=new URL(raw,location.origin);return (u.protocol==='https:'||u.origin===location.origin)&&!u.username&&!u.password?u.href:null;}catch{return null;}};
 async function refresh(){
  try{
   const r=await fetch('/api/v1/public/landing-data',{signal:AbortSignal.timeout(8000)}),body=await r.json();
   if(!r.ok||body.success!==true||!Array.isArray(body.data?.rows)||!Array.isArray(body.data?.channels))throw Error('Unavailable');
   const rows=body.data.rows.filter(row=>row.serviceTypeCode==='AIRPORT_PICKUP');
   if(!rows.length)throw Error('No active pickup routes');
   for(const row of rows){if(typeof row.origin!=='string'||typeof row.destination!=='string')throw Error('Invalid route');
    for(const vehicle of ['SEDAN','SUV','VAN']){const price=row.prices?.[vehicle];if(typeof price!=='number'||!Number.isFinite(price)||price<=0)throw Error('Invalid fare');}}
   const hero=rows.find(r=>r.origin==='BKK'&&r.destination==='PATTAYA');if(!hero)throw Error('Missing hero route');
   const airports=[...new Set(rows.map(r=>r.origin))],selected=document.querySelector('[data-airport][aria-pressed="true"]')?.dataset.airport;
   const airport=airports.includes(selected)?selected:airports[0],tbody=document.createDocumentFragment(),tabs=document.createDocumentFragment();
   for(const code of airports){const button=document.createElement('button');button.dataset.airport=code;button.setAttribute('aria-pressed',String(code===airport));button.textContent=(data.places[code]||rows.find(r=>r.origin===code).originLabel||code)+' '+code;tabs.append(button);}
   for(const row of rows){const tr=document.createElement('tr');tr.dataset.airportRow=row.origin;tr.dataset.destination=row.destination;tr.hidden=row.origin!==airport;
    const th=document.createElement('th');th.scope='row';th.textContent=data.places[row.destination]||row.label||row.destination;tr.append(th);
    for(const vehicle of ['SEDAN','SUV','VAN']){const td=document.createElement('td');td.dataset.price=vehicle;td.textContent=row.prices[vehicle].toLocaleString('en-US');tr.append(td);}tbody.append(tr);}
   document.querySelector('tbody').replaceChildren(tbody);document.querySelector('.airport-tabs').replaceChildren(tabs);document.querySelector('#hero-price-amount').textContent=hero.prices.SEDAN.toLocaleString('en-US');
   const channels=[...body.data.channels].sort((a,b)=>data.contactOrder.indexOf(a.code)-data.contactOrder.indexOf(b.code));
   const links=channels.flatMap(c=>{if(!data.channels[c.code])return[];const digits=(c.phoneNumber||'').replace(/\D/g,'');const raw=c.code==='WHATSAPP'?(digits?`https://wa.me/${digits}`:null):(c.addUrl||`/support?lang=${data.lang}`);if(!raw)return[];const url=allowedContact(raw);if(!url)return[];const a=document.createElement('a');a.dataset.channel=c.code;a.href=url;a.rel='noopener noreferrer';a.target='_blank';a.textContent=data.channels[c.code]+data.contactSuffix;return[a];});
   const heroSupport=document.querySelector('#hero-support');if(heroSupport&&links.length){const first=links[0].cloneNode(true);first.className='service';first.textContent=data.heroContact.replace('{channel}',data.channels[channels[0].code]);heroSupport.replaceChildren(first);}
   const parent=document.querySelector('#support-actions');parent.querySelectorAll('[data-channel]').forEach(a=>a.remove());links.forEach(a=>parent.insertBefore(a,parent.lastElementChild));
   document.querySelector('#fare-status').textContent=data.fareMessages[0];
  }catch{document.querySelector('#fare-status').textContent=data.fareMessages[1]+' ('+data.snapshotDate+')';}
 }
 requestAnimationFrame(()=>setTimeout(refresh,0));
})();
