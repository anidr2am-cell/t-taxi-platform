'use strict';
const fs=require('node:fs');
const base=process.argv[2],url=new URL(base||'');
if(!((url.protocol==='https:'&&url.hostname.endsWith('.trycloudflare.com'))||(url.protocol==='http:'&&url.hostname==='159.89.192.55'&&url.port)))throw Error('Use the isolated preview origin');
if(url.pathname!=='/'||url.search||url.hash)throw Error('Origin must not include a path');
(async()=>{const r=await fetch(url.origin+'/api/v1/public/landing-data'),body=await r.json();if(!r.ok||body.success!==true||!body.data?.rows?.length)throw Error('Landing API unavailable');
fs.writeFileSync('landing/snapshot.json',JSON.stringify({capturedAt:body.data.updatedAt,fareSource:url.origin,contactSource:url.origin+'/api/v1/public/landing-data',rows:body.data.rows,channels:body.data.channels},null,2)+'\n');console.log(JSON.stringify({routes:body.data.rows.length,channels:body.data.channels.map(c=>c.code)}));})().catch(e=>{console.error(e.message);process.exit(1)});
