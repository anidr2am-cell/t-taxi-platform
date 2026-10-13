'use strict';
(() => {
 const data=JSON.parse(document.querySelector('#landing-data').textContent);
 const status=document.querySelector('#fare-status');let requestId=0;
 const money=n=>new Intl.NumberFormat('ko-KR').format(n);
 const allowedContact=raw=>{try{const u=new URL(raw);return u.protocol==='https:'&&!u.username&&!u.password?u.href:null;}catch{return null;}};
 async function refreshFares(airport){
  const id=++requestId;status.textContent='최신 요금을 확인하고 있어요…';
  const rows=data.rows.filter(row=>row.airport===airport);let failed=false;
  await Promise.all(rows.map(async row=>{
   await Promise.all(['SEDAN','SUV','VAN'].map(async vehicle=>{
    try{
     const r=await fetch('/api/v1/bookings/pricing/calculate',{method:'POST',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(8000),body:JSON.stringify({serviceTypeCode:'AIRPORT_PICKUP',vehicleTypeCode:vehicle,vehicleCount:1,originLocationCode:airport,destinationLocationCode:row.destination,options:{}})});
     const body=await r.json();const total=body?.data?.totalAmount;
     if(!r.ok||body.success!==true||typeof total!=='number'||!Number.isFinite(total)||total<=0)throw Error('Quote unavailable');
     if(id!==requestId)return;
     const cell=document.querySelector(`[data-airport-row="${airport}"][data-destination="${row.destination}"] [data-price="${vehicle}"]`);cell.textContent=money(total);
    }catch{failed=true;}
   }));
  }));
  if(id===requestId)status.textContent=failed?`일부 최신 요금을 확인하지 못했어요. ${data.snapshotDate} 기본 요금이며, 예약 화면에서 최종 확인해 주세요.`:'최신 견적 API 확인 완료 · 상세 주소·옵션은 예약 화면에서 최종 확인';
 }
 document.querySelectorAll('[data-airport]').forEach(button=>button.addEventListener('click',()=>{
  const airport=button.dataset.airport;document.querySelectorAll('[data-airport]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
  document.querySelectorAll('[data-airport-row]').forEach(r=>r.hidden=r.dataset.airportRow!==airport);refreshFares(airport);
 }));
 // Same storage contract as Flutter. No gtag request is made in this preview.
 const key='tride_analytics_consent';
 const read=()=>{try{return localStorage.getItem(key);}catch{return null;}};
 const banner=document.querySelector('#cookie-banner');
 function save(value){try{localStorage.setItem(key,value);if(value==='denied'){localStorage.removeItem('tride_marketing_first_touch');localStorage.removeItem('tride_marketing_last_touch');}}catch{}banner.hidden=true;if(value==='granted')captureAttribution();}
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
 banner.hidden=['granted','denied'].includes(read());if(read()==='granted')captureAttribution();
 // The snapshot preserves actual public configured links if isolated STG has none.
 fetch('/api/v1/bookings/contact-channels/public',{signal:AbortSignal.timeout(8000)}).then(r=>r.ok?r.json():Promise.reject()).then(body=>{
  const channels=body?.data?.channels;if(!Array.isArray(channels)||channels.length===0)return;
  const parent=document.querySelector('#support-actions');const names={KAKAO:'카카오톡',LINE:'LINE',WHATSAPP:'WhatsApp'};
  const links=channels.flatMap(c=>{if(!names[c.code])return[];const raw=c.code==='WHATSAPP'?`https://wa.me/${(c.phoneNumber||'').replace(/\D/g,'')}`:c.addUrl;const url=allowedContact(raw);if(!url)return[];const a=document.createElement('a');a.dataset.channel=c.code;a.href=url;a.rel='noopener noreferrer';a.target='_blank';a.textContent=names[c.code]+'으로 문의';return[a];});
  parent.querySelectorAll('[data-channel]').forEach(a=>a.remove());links.forEach(a=>parent.insertBefore(a,parent.lastElementChild));
 }).catch(()=>{});
 // Defer non-critical fare calls until the first frame is painted.
 requestAnimationFrame(()=>setTimeout(()=>refreshFares('BKK'),0));
})();
