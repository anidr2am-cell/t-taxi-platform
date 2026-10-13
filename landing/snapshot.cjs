const fs=require('node:fs');
const base=process.argv[2];if(!/^http:\/\/159\.89\.192\.55:\d+$/.test(base||''))throw Error('Use isolated preview origin');
const destinations={PATTAYA:'파타야',BANGKOK:'방콕',HUA_HIN:'후아힌',RAYONG:'라용',AYUTTHAYA:'아유타야'};
(async()=>{
 const rows=[];for(const airport of ['BKK','DMK'])for(const destination of (airport==='BKK'?['PATTAYA','BANGKOK','HUA_HIN','RAYONG','AYUTTHAYA']:['PATTAYA','BANGKOK','HUA_HIN','RAYONG'])){
 const prices={};for(const vehicle of ['SEDAN','SUV','VAN']){
 const input={serviceTypeCode:'AIRPORT_PICKUP',vehicleTypeCode:vehicle,originLocationCode:airport,destinationLocationCode:destination,vehicleCount:1,options:{}};
 const r=await fetch(base+'/api/v1/bookings/pricing/calculate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});const body=await r.json();
 if(r.status!==200||!body.success||typeof body.data.totalAmount!=='number'||body.data.totalAmount<=0)throw Error(JSON.stringify({airport,destination,vehicle,body}));prices[vehicle]=body.data.totalAmount;
 }rows.push({airport,destination,label:destinations[destination],prices});}
 // Only public support settings; no production DB access or writes.
 const r=await fetch('https://trider.taxi/api/v1/bookings/contact-channels/public');if(!r.ok)throw Error('Public channel settings unavailable');const settings=await r.json();
 const snapshot={capturedAt:new Date().toISOString(),fareSource:base,contactSource:'https://trider.taxi/api/v1/bookings/contact-channels/public',rows,channels:settings.data.channels.filter(c=>['KAKAO','LINE','WHATSAPP'].includes(c.code)),capacity:[{code:'SEDAN',people:2,small:2,large:0,golf:0},{code:'SUV',people:3,small:2,large:2,golf:1},{code:'VAN',people:8,small:8,large:8,golf:4}]};
 fs.writeFileSync('landing/snapshot.json',JSON.stringify(snapshot,null,2));console.log(JSON.stringify({routes:rows.length,quotes:rows.length*3,channels:snapshot.channels.map(c=>c.code),example:rows[0]}));
})().catch(e=>{console.error(e.message);process.exit(1)});
