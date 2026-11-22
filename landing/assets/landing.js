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
  window.gtag('js',new Date());window.gtag('config',data.measurementId,{send_page_view:true,anonymize_ip:true,page_location:location.origin+location.pathname,page_referrer:document.referrer?new URL(document.referrer).origin:'',...window.trideMarketing.campaignParams()});
  const script=document.createElement('script');script.async=true;script.src='https://www.googletagmanager.com/gtag/js?id='+encodeURIComponent(data.measurementId);document.head.append(script);
 }
 function event(name,details){if(read()!=='granted')return;analytics();if(initialized)window.gtag('event',name,{language:data.lang,...details});}
 function save(value){try{localStorage.setItem(key,value);if(value==='denied'){localStorage.removeItem('tride_marketing_first_touch');localStorage.removeItem('tride_marketing_last_touch');}}catch{}banner.hidden=true;window['ga-disable-'+data.measurementId]=value!=='granted';
  if(value==='granted'){captureAttribution();if(initialized)window.gtag('consent','update',{analytics_storage:'granted'});analytics();}else if(initialized)window.gtag('consent','update',{analytics_storage:'denied'});
 }
 function captureAttribution(){window.trideMarketing.capture();}

 document.querySelector('#cookie-accept').addEventListener('click',()=>save('granted'));
 document.querySelector('#cookie-deny').addEventListener('click',()=>save('denied'));
 document.querySelector('#consent-settings').addEventListener('click',()=>banner.hidden=false);
 banner.hidden=['granted','denied'].includes(read());if(read()==='granted'){captureAttribution();analytics();}
 const form=document.querySelector('#quick-booking'),status=document.querySelector('#quick-status');
 const endpoints={from:null,to:null},generations={from:0,to:0},timers={},phases={from:'editing',to:'editing'};
 let savedForm=null;try{const raw=JSON.parse(sessionStorage.getItem('tride_landing_form_v1'));if(raw?.expiresAt>Date.now())savedForm=raw;else sessionStorage.removeItem('tride_landing_form_v1');}catch{}
 const explicitService=new URL(location.href).searchParams.get('service');
 let service=explicitService||savedForm?.service||'AIRPORT_PICKUP';
 function phase(side,value){phases[side]=value;const busy=Object.values(phases).some(p=>p==='searching'||p==='selecting');form.setAttribute('aria-busy',String(busy));for(const button of document.querySelectorAll('.primary-action,#mobile-booking-bar button')){button.disabled=busy;button.textContent=busy?data.ux.loading:(service==='GOLF_TRANSFER'?data.ux.continue:data.ux.check);}}
 function validEndpoint(value){return value&&typeof value.name==='string'&&value.name.trim()&&Number.isFinite(value.latitude)&&Math.abs(value.latitude)<=90&&Number.isFinite(value.longitude)&&Math.abs(value.longitude)<=180;}
 function saveQuickForm(){try{sessionStorage.setItem('tride_landing_form_v1',JSON.stringify({service,endpoints,inputs:{from:document.querySelector('#quick-from').value,to:document.querySelector('#quick-to').value},expiresAt:Date.now()+4*60*60*1000}));}catch{}}
 if(!['AIRPORT_PICKUP','AIRPORT_DROPOFF','CITY_TRANSFER','GOLF_TRANSFER'].includes(service))service='AIRPORT_PICKUP';
 const airports={BKK:{lat:13.689999,lng:100.747924,name:'BKK — Suvarnabhumi Airport'},DMK:{lat:13.913260,lng:100.602010,name:'DMK — Don Mueang Airport'},UTP:{lat:12.679944,lng:101.005028,name:'UTP — U-Tapao Airport'}};
 const place=(id,name,address,lat,lng,code)=>({id,displayName:name,name,address,latitude:lat,longitude:lng,kind:code?'airport':'place',code:code||null});
 function selectService(next){service=next;for(const side of ['from','to']){const airport=(side==='from'&&service==='AIRPORT_PICKUP')||(side==='to'&&service==='AIRPORT_DROPOFF');document.querySelector('#airport-'+side).hidden=!airport;document.querySelector('#quick-'+side).hidden=airport;endpoints[side]=null;document.querySelector('#quick-'+side).value='';document.querySelector('#airport-'+side).value='';document.querySelector('#results-'+side).replaceChildren();generations[side]++;document.querySelector('#retry-'+side).hidden=true;phase(side,'editing');}document.querySelectorAll('[data-service]').forEach(a=>a.setAttribute('aria-current',String(a.dataset.service===service)));document.querySelector('#quick-skip').href='/booking?service='+service+'&lang='+data.lang;status.textContent='';}
 selectService(service);
 if(!explicitService&&savedForm?.service===service){for(const side of ['from','to']){endpoints[side]=savedForm.endpoints?.[side]||null;document.querySelector('#quick-'+side).value=endpoints[side]?.name||savedForm.inputs?.[side]||'';document.querySelector('#airport-'+side).value=endpoints[side]?.code||'';phase(side,validEndpoint(endpoints[side])?'selected':'editing');}}
 document.querySelectorAll('[data-service]').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();selectService(a.dataset.service);saveQuickForm();event('landing_service_click',{service_type:service});}));
 for(const side of ['from','to']){
  document.querySelector('#airport-'+side).addEventListener('change',e=>{e.target.removeAttribute('aria-invalid');document.querySelector('#error-'+side).hidden=true;const a=airports[e.target.value];endpoints[side]=a?place('airport:'+e.target.value,a.name,a.name,a.lat,a.lng,e.target.value):null;phase(side,endpoints[side]?'selected':'editing');saveQuickForm();});
  const input=document.querySelector('#quick-'+side),results=document.querySelector('#results-'+side),retry=document.querySelector('#retry-'+side);retry.addEventListener('click',()=>input.dispatchEvent(new Event('input',{bubbles:true})));
  input.addEventListener('blur',saveQuickForm);
  input.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){const first=results.querySelector('button');if(first){e.preventDefault();first.focus();}}if(e.key==='Escape'){results.replaceChildren();generations[side]++;clearTimeout(timers[side]);phase(side,'editing');status.textContent='';}});
  input.addEventListener('input',()=>{input.removeAttribute('aria-invalid');document.querySelector('#error-'+side).hidden=true;retry.hidden=true;phase(side,'editing');endpoints[side]=null;saveQuickForm();const generation=++generations[side];clearTimeout(timers[side]);results.replaceChildren();const query=input.value.trim();if(query.length<2)return;timers[side]=setTimeout(async()=>{phase(side,'searching');status.textContent=data.ux.loading;try{const r=await fetch('/api/v1/places/autocomplete?'+new URLSearchParams({input:query,language:data.lang}),{signal:AbortSignal.timeout(8000)});const body=await r.json();if(!r.ok||body.success===false)throw Error();if(generation!==generations[side])return;phase(side,'editing');const rows=body.data?.predictions||body.predictions||[];if(!Array.isArray(rows))throw Error();status.textContent=rows.length?'':data.ux.empty;if(!rows.length){phase(side,'error');retry.hidden=false;}for(const row of rows.slice(0,5)){const id=row.placeId||row.place_id;if(!id)continue;const button=document.createElement('button');button.type='button';button.textContent=row.mainText||row.structured_formatting?.main_text||row.description;const detail=document.createElement('small');detail.textContent=row.secondaryText||row.structured_formatting?.secondary_text||'';button.append(detail);button.addEventListener('click',async()=>{const selection=++generations[side];phase(side,'selecting');document.querySelector('#error-'+side).hidden=true;input.value=row.mainText||row.structured_formatting?.main_text||row.description;status.textContent=data.ux.loading;try{const r=await fetch('/api/v1/places/details?'+new URLSearchParams({placeId:id,language:data.lang}),{signal:AbortSignal.timeout(8000)});const body=await r.json();if(!r.ok||body.success===false)throw Error();if(selection!==generations[side])return;const d=body.data?.place||body.data||body.place||body;const lat=Number(d.lat??d.latitude),lng=Number(d.lng??d.longitude);if(typeof d.name!=='string'||!d.name.trim()||!Number.isFinite(lat)||!Number.isFinite(lng)||Math.abs(lat)>90||Math.abs(lng)>180)throw Error();endpoints[side]=place('place:'+id,d.name,d.formattedAddress||d.formatted_address||d.address||'',lat,lng);input.value=d.name;results.replaceChildren();phase(side,'selected');status.textContent='';saveQuickForm();}catch{if(selection===generations[side]){phase(side,'error');retry.hidden=false;status.textContent=data.ux.error;}}});results.append(button);}}catch{if(generation===generations[side]){phase(side,'error');retry.hidden=false;status.textContent=data.ux.error;}}},300);});
 }
 form.addEventListener('submit',e=>{e.preventDefault();if(Object.values(phases).some(p=>p==='searching'||p==='selecting')){status.textContent=data.ux.loading;return;}if(!validEndpoint(endpoints.from)||!validEndpoint(endpoints.to)){status.textContent='';const side=!endpoints.from?'from':'to',field=document.querySelector('#airport-'+side).hidden?document.querySelector('#quick-'+side):document.querySelector('#airport-'+side);const error=document.querySelector('#error-'+side);error.textContent=field.tagName==='SELECT'?data.ux.airport:data.ux.select;error.hidden=false;field.setAttribute('aria-invalid','true');field.focus();field.scrollIntoView({block:'center',behavior:'smooth'});return;}const entry=crypto.randomUUID();try{sessionStorage.setItem('tride_landing_route_v1',JSON.stringify({entry,service,expiresAt:Date.now()+4*60*60*1000,origin:endpoints.from,destination:endpoints.to}));}catch{status.textContent=data.ux.error;return;}event('landing_booking_start',{service_type:service});const url=new URL('/booking',location.origin);url.search=new URLSearchParams({service,lang:data.lang,entry});location.href=window.trideMarketing.decorateUrl(url.href);});
 document.querySelector('#language-select').addEventListener('change',e=>{const lang=e.target.value;if(!['ko','en','th','ja','zh','zh-TW'].includes(lang))return;saveQuickForm();event('landing_language_change',{destination_language:lang});location.href=window.trideMarketing.decorateUrl(lang==='ko'?'/':`/${lang}/`);});
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
    for(const vehicle of ['SEDAN','SUV','VAN']){const td=document.createElement('td');td.dataset.price=vehicle;const button=document.createElement('button');button.type='button';button.className='route-fare';button.dataset.routeVehicle=vehicle;button.textContent=row.prices[vehicle].toLocaleString('en-US');button.setAttribute('aria-label',data.ux.design.route+' · '+row.origin+' → '+(data.places[row.destination]||row.label)+' · '+data.vehicles[['SEDAN','SUV','VAN'].indexOf(vehicle)]);td.append(button);tr.append(td);}tbody.append(tr);}
   document.querySelector('tbody').replaceChildren(tbody);document.querySelector('.airport-tabs').replaceChildren(tabs);document.querySelector('#hero-price-amount').textContent=hero.prices.SEDAN.toLocaleString('en-US');
   const byCode=new Map(body.data.channels.map(c=>[c.code,c]));
   const channels=data.contactOrder.map(code=>byCode.get(code)).filter(Boolean);
   const links=channels.flatMap(c=>{if(!data.channels[c.code])return[];const digits=(c.phoneNumber||'').replace(/\D/g,'');const raw=c.code==='WHATSAPP'?(digits?`https://wa.me/${digits}`:null):(c.addUrl||`/support?lang=${data.lang}`);if(!raw)return[];const url=allowedContact(raw);if(!url)return[];const a=document.createElement('a');a.dataset.channel=c.code;a.dataset.preferred=String(c.code===data.preferredChannel);a.href=url;a.rel='noopener noreferrer';a.target='_blank';a.textContent=data.channels[c.code]+data.contactSuffix+(c.code===data.preferredChannel?' · '+data.ux.design.preferred:'');return[a];});
   const parent=document.querySelector('#support-actions');parent.querySelectorAll('[data-channel]').forEach(a=>a.remove());links.forEach(a=>parent.insertBefore(a,parent.lastElementChild));
   document.querySelector('#fare-status').textContent=data.fareMessages[0];
  }catch{document.querySelector('#fare-status').textContent=data.fareMessages[1]+' ('+data.snapshotDate+')';}
 }

 // A representative route is a search starting point, never a substituted hotel address.
 document.querySelector('tbody').addEventListener('click',e=>{const button=e.target.closest('[data-route-vehicle]');if(!button)return;const row=button.closest('tr');selectService('AIRPORT_PICKUP');const airport=document.querySelector('#airport-from');airport.value=row.dataset.airportRow;airport.dispatchEvent(new Event('change'));const destination=document.querySelector('#quick-to');destination.value=data.places[row.dataset.destination]||row.dataset.destination;saveQuickForm();status.textContent=data.ux.design.region;document.querySelector('#booking-start').scrollIntoView({block:'start'});destination.focus({preventScroll:true});});
 const bar=document.querySelector('#mobile-booking-bar');
 function updateChrome(){const cookie= banner.hidden?0:banner.getBoundingClientRect().height;document.documentElement.style.setProperty('--cookie-height',Math.ceil(cookie)+'px');const vv=window.visualViewport;const keyboard=!!vv&&vv.height<document.documentElement.clientHeight*0.78&&/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName||'');document.body.classList.toggle('keyboard-open',keyboard);const rect=form.querySelector('.primary-action').getBoundingClientRect();bar.classList.toggle('is-obscured',rect.top>=0&&rect.bottom<=(vv?.height||innerHeight)-cookie);}
 new ResizeObserver(updateChrome).observe(banner);new MutationObserver(updateChrome).observe(banner,{attributes:true,attributeFilter:['hidden']});window.addEventListener('scroll',updateChrome,{passive:true});window.addEventListener('resize',updateChrome);window.visualViewport?.addEventListener('resize',updateChrome);document.addEventListener('focusin',updateChrome);document.addEventListener('focusout',()=>setTimeout(updateChrome,100));updateChrome();

 requestAnimationFrame(()=>setTimeout(refresh,0));
})();
