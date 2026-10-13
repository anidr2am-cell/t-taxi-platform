const fs=require('node:fs'),path=require('node:path');
const root=__dirname,snapshot=JSON.parse(fs.readFileSync(path.join(root,'snapshot.json'),'utf8').replace(/^\uFEFF/,''));
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Bangkok'}).format(new Date(snapshot.capturedAt));
const fareRows=snapshot.rows.map(r=>`<tr data-airport-row="${r.airport}" data-destination="${r.destination}"${r.airport==='BKK'?'':' hidden'}><th scope="row">${esc(r.label)}</th>${['SEDAN','SUV','VAN'].map(v=>`<td data-price="${v}">${r.prices[v].toLocaleString('en-US')}</td>`).join('')}</tr>`).join('\n');
const vehicleNames={SEDAN:'세단',SUV:'SUV',VAN:'밴'};
function art(v){const van=v==='VAN';return `<svg class="vehicle-art" viewBox="0 0 300 140" role="img" aria-label="${vehicleNames[v]} 차량 일러스트, 실사진 교체 가능"><ellipse cx="150" cy="114" rx="119" ry="9" fill="#EEF2F4"/><path d="${van?'M36 95V37Q36 25 50 25h170q24 0 30 25l15 31v18H36z':'M28 94V74q0-10 14-13l25-6 28-30h90l35 37 39 7q14 3 14 17v13H28z'}" fill="${van?'#084F50':v==='SUV'?'#0B6E6E':'#DDE5E8'}"/><path d="${van?'M52 36h164l16 36H52z':'M100 35h78l26 27H78z'}" fill="#b6d7db"/><path d="M144 34v29" stroke="#fff" stroke-width="4"/><circle cx="80" cy="100" r="19" fill="#1E2A32"/><circle cx="224" cy="100" r="19" fill="#1E2A32"/><circle cx="80" cy="100" r="9" fill="#DDE5E8"/><circle cx="224" cy="100" r="9" fill="#DDE5E8"/><path d="M32 79h20m193 0h20" stroke="#C9922E" stroke-width="6"/></svg>`;}
const vehicles=snapshot.capacity.map(v=>`<article class="vehicle">${art(v.code)}<div class="vehicle-header"><h3>${vehicleNames[v.code]}</h3><span>${v.code}</span></div><dl><dt>승객</dt><dd>최대 ${v.people}명</dd><dt>20인치 캐리어</dt><dd>최대 ${v.small}개</dd><dt>24인치 이상 캐리어</dt><dd>${v.large?`최대 ${v.large}개`:'해당 규칙 수용 없음'}</dd><dt>골프백</dt><dd>${v.golf?`최대 ${v.golf}개`:'다른 차량 추천 확인'}</dd></dl></article>`).join('\n');
const faq=[
 ['표시 요금에 무엇이 포함되나요?','고속도로 통행료·공항 주차비·항공편 지연 대기는 요금에 포함됩니다. 상세 주소에 따른 거리 추가요금과 피켓 선택 비용은 예약 화면의 최종 요금에서 확인할 수 있습니다.'],
 ['항공편이 지연되면 어떻게 하나요?','항공편 지연 시 실제 도착 시각에 맞춰 픽업을 안내합니다. 공항 픽업 예약에서 항공편 정보를 입력하고, 변경 사항이 있으면 고객센터에 알려주세요.'],
 ['결제는 어떻게 하나요?','현금은 목적지에 도착한 뒤 기사에게 직접 결제합니다. 원화·바트 계좌이체는 관리자에 등록된 계좌·QR 안내를 확인하고, 카드결제는 관리자를 통해 진행합니다.'],
 ['예약 취소와 환불은 어떻게 하나요?','운행 시작 전이며 픽업 예정 시각까지 2시간보다 많이 남은 예약은 예약 조회에서 취소할 수 있습니다. 현재 정책은 취소 수수료 없이 전액 환불이며, 픽업이 임박했거나 이미 결제한 경우 고객센터에 문의해 주세요.'],
 ['캐리어나 골프백이 많아도 되나요?','인원과 캐리어 크기·개수, 골프백을 예약 화면에 입력해 주세요. 실제 조합에 맞는 추천 차량을 확인할 수 있습니다. 차량 한도를 넘거나 특수 짐이 있으면 고객센터로 문의해 주세요.'],
 ['어린이와 유아는 어떻게 입력하나요?','어린이와 유아도 승객 수에 포함됩니다. 예약 화면에서 성인·어린이·유아를 각각 입력해 주세요. 유아용 좌석이 필요하면 예약 전 고객센터에 확인해 주세요.'],
 ['예약 후에는 어떻게 연락하나요?','예약에서 선택한 연락 방법으로 안내를 받을 수 있도록 정보를 정확히 입력해 주세요. 카카오톡·LINE 이용 고객은 완료 화면의 공식 채널 연결 버튼으로 예약번호를 보내주세요.'],
 ['회원가입 없이도 예약을 확인할 수 있나요?','예약번호와 전화번호로 비회원 예약 조회가 가능합니다. 전화번호 없이 LINE으로 예약한 경우 같은 기기의 예약 정보 또는 공식 고객센터를 이용해 주세요. 로그인하면 다른 기기에서도 내 예약을 확인할 수 있습니다.']
].map(([q,a])=>`<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join('\n');
const names={KAKAO:'카카오톡',LINE:'LINE',WHATSAPP:'WhatsApp'};
const contacts=[...snapshot.channels].sort((a,b)=>['KAKAO','LINE','WHATSAPP'].indexOf(a.code)-['KAKAO','LINE','WHATSAPP'].indexOf(b.code)).map(c=>{const url=c.code==='WHATSAPP'?`https://wa.me/${c.phoneNumber.replace(/\D/g,'')}`:c.addUrl;if(!url.startsWith('https://'))throw Error('Unsafe public contact URL');return `<a data-channel="${c.code}" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${names[c.code]}으로 문의</a>`;}).join('');
let html=fs.readFileSync(path.join(root,'index.template.html'),'utf8');for(const [key,value]of Object.entries({FARE_ROWS:fareRows,VEHICLES:vehicles,FAQ:faq,CONTACTS:contacts,SNAPSHOT_DATE:date,DATA:JSON.stringify({rows:snapshot.rows,snapshotDate:date,analyticsEnabled:false}).replace(/</g,'\\u003c')}))html=html.replaceAll('{{'+key+'}}',value);
fs.mkdirSync(path.join(root,'dist'),{recursive:true});fs.writeFileSync(path.join(root,'dist','index.html'),html);fs.cpSync(path.join(root,'assets'),path.join(root,'dist','landing-assets'),{recursive:true});console.log('Built Korean static landing; analytics disabled; no external font.');
