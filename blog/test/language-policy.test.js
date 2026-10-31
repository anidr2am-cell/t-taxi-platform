import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import matter from 'gray-matter';
const root=path.resolve(import.meta.dirname,'../..');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'trider-language-policy-'));
const blog=path.join(temp,'blog'),landing=path.join(temp,'landing');
execFileSync(process.execPath,['blog/build.js'],{cwd:root,env:{...process.env,BLOG_DIST_DIR:blog}});
execFileSync(process.execPath,['landing/build.cjs'],{cwd:root,env:{...process.env,LANDING_DIST_DIR:landing}});
const posts=fs.readdirSync(path.join(root,'blog/posts')).filter(n=>n.endsWith('.md')).map(n=>matter(fs.readFileSync(path.join(root,'blog/posts',n),'utf8')).data);
const read=(dir,part)=>fs.readFileSync(path.join(dir,part,'index.html'),'utf8');
const forbidden=/최저가\s*보장|차액\s*환불|price[ -]match|lowest[ -]price|価格保証|最安値保証|价格保[障证]|最低价保证|รับประกันราคาต่ำสุด/i;
test('landing guide links retain the existing blog language and English SEO is specific',()=>{
 for(const lang of ['ko','en','ja','zh','th']){
  const html=read(landing,lang==='ko'?'':lang),expected=['en','ja','zh'].includes(lang)?`/blog/lang/${lang}/`:'/blog/';
  assert.ok(html.includes(`href="${expected}"`),lang);
 }
 const en=read(landing,'en');assert.match(en,/<title>[^<]*Tolls &amp; airport parking included/);assert.doesNotMatch(en,/<title>[^<]*No extra charges/);
 assert.match(en,/optional name.sign/);assert.match(en,/address-based distance charge/);
});
test('all blog headers, article CTAs and inline booking links preserve page language',()=>{
 for(const post of posts){
  const html=read(blog,post.slug),links=[...html.matchAll(/href="([^"#]+)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&'),'https://trider.taxi'));
  const booking=links.filter(u=>u.origin==='https://trider.taxi'&&['/','/booking'].includes(u.pathname));
  assert(booking.length>=2,post.slug);for(const url of booking){assert.equal(url.pathname,'/booking',post.slug);assert.equal(url.searchParams.get('lang'),post.lang,post.slug);}
 }
 for(const lang of ['en','ja','zh','ru']) assert.ok(read(blog,`lang/${lang}`).includes(`/booking?lang=${lang}`));
});
test('guarantees disappear from published body, list, related cards, titles, metadata and JSON-LD; legacy slugs remain',()=>{
 function audit(dir){for(const item of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,item.name);if(item.isDirectory())audit(p);else if(item.name.endsWith('.html')){
  // The published URL/translation identity is intentionally unchanged.
  const html=fs.readFileSync(p,'utf8').replaceAll(/pattaya-golf-price-match-guarantee(?:-(?:en|ja|zh))?/g,'legacy-golf-guide');assert.doesNotMatch(html,forbidden,p);
 }}}audit(blog);
 for(const suffix of ['','-en','-ja','-zh','-ru']){const slug='pattaya-golf-price-match-guarantee'+suffix,html=read(blog,slug);assert.ok(html.includes('https://trider.taxi/blog/'+slug));assert.match(html,/"@type":"Article"/);const updated=fs.readFileSync(path.join(root,'blog/posts',slug+'.md'),'utf8').match(/^updated:\s*(\S+)/m)[1];assert.ok(html.includes('"dateModified":"'+updated+'"'));}
 const sitemap=fs.readFileSync(path.join(blog,'sitemap-blog.xml'),'utf8');for(const post of posts)assert.ok(sitemap.includes('/blog/'+post.slug+'</loc>'),post.slug);
});
test.after(()=>fs.rmSync(temp,{recursive:true,force:true}));

test('airport and localized golf guides preset the correct service without changing other CTAs',()=>{
 const slug='pattaya-to-airport-transfer-en',html=read(blog,slug);
 const expected='/booking?service=AIRPORT_DROPOFF&amp;lang=en';
 assert.equal((html.match(/href="\/booking[^"]*"/g)||[]).length,3);
 assert.equal(html.split('href="'+expected+'"').length-1,3);
 assert.ok(html.includes('>Book your airport drop-off in English</a>'));
 const pickupSlug='suvarnabhumi-to-pattaya-en',pickup=read(blog,pickupSlug);
 const pickupLinks=[...pickup.matchAll(/href="(\/booking[^\"]*)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&'),'https://trider.taxi'));
 assert.equal(pickupLinks.length,5);
 for(const url of pickupLinks){assert.equal(url.searchParams.get('service'),'AIRPORT_PICKUP');assert.equal(url.searchParams.get('lang'),'en');assert.equal(url.searchParams.has('utm_source'),false);}
 assert.match(pickup,/<aside class="cta"><strong>✈️ Airport pickup/);
 const guideSlug='suvarnabhumi-airport-pickup-guide-en',guide=read(blog,guideSlug);
 const guideLinks=[...guide.matchAll(/href="(\/booking[^\"]*)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&'),'https://trider.taxi'));
 assert.equal(guideLinks.length,4);
 for(const url of guideLinks){assert.equal(url.searchParams.get('service'),'AIRPORT_PICKUP');assert.equal(url.searchParams.get('lang'),'en');assert.equal(url.searchParams.has('utm_source'),false);}
 assert.match(guide,/<aside class="cta"><strong>✈️ Airport pickup/);
 assert.ok(guide.includes('address-based distance charge'));
 assert.doesNotMatch(guide,/with no extra charges/);
 const checklist=read(blog,'thailand-airport-taxi-booking-guide-en');
 const checklistLinks=[...checklist.matchAll(/href="(\/booking[^\"]*)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&'),'https://trider.taxi'));
 assert.equal(checklistLinks.length,3);
 for(const url of checklistLinks){assert.equal(url.searchParams.get('lang'),'en');assert.equal(url.searchParams.has('service'),false);assert.equal(url.searchParams.has('utm_source'),false);}
 assert.match(checklist,/Airport pickup: airport to accommodation/);
 assert.match(checklist,/Airport drop-off: accommodation to airport/);
 assert.ok(checklist.includes('https://wa.me/66815693445'));
 assert.ok(checklist.includes('/blog/pattaya-to-airport-transfer-en'));
 assert.match(checklist,/final total/);
 assert.doesNotMatch(checklist,/child seat|unlimited waiting|with no extra charges/i);
 const topicPosts=posts.filter(p=>p.category==='golf'||p.translationKey==='pattaya-to-airport-transfer');
 const golfLabels={ko:/골프장/,en:/Golf course/,ja:/ゴルフ場/,zh:/高尔夫球场/,ru:/гольфа/};
 const dropoffLabels={ko:/공항 샌딩/,en:/to the airport/,ja:/空港への/,zh:/送机/,ru:/в аэропорт/};
 for(const post of topicPosts){
  const service=post.category==='golf'?'GOLF_TRANSFER':'AIRPORT_DROPOFF',lang=post.lang;
  assert.equal(post.bookingService,service,post.slug);
  const page=read(blog,post.slug),expectedTopic='/booking?service='+service+'&amp;lang='+lang;
  assert.ok(page.includes('class="book-button" href="'+expectedTopic+'"'),post.slug);
  assert.ok(page.includes('class="cta-primary" href="'+expectedTopic+'"'),post.slug);
  const title=page.match(/<aside class="cta"><strong>([^<]+)<\/strong>/)?.[1];
  assert.match(title,(post.category==='golf'?golfLabels:dropoffLabels)[post.lang],post.slug);
  if(post.category==='golf')assert.doesNotMatch(title,/공항|airport|空港|机场|аэропорт/i,post.slug);
  const bookingLinks=[...page.matchAll(/href="(\/booking[^\"]*)"/g)].map(m=>new URL(m[1].replaceAll('&amp;','&'),'https://trider.taxi'));
  assert.ok(bookingLinks.length>=2,post.slug);
  for(const url of bookingLinks){assert.equal(url.searchParams.get('service'),service,post.slug);assert.equal(url.searchParams.get('lang'),lang,post.slug);assert.equal(url.searchParams.has('utm_source'),false,post.slug);}
 }
 for(const post of posts.filter(p=>![pickupSlug,guideSlug,...topicPosts.map(p=>p.slug)].includes(p.slug))){
  const page=read(blog,post.slug);
  const bookingLang=post.lang;
  assert.ok(page.includes('class="book-button" href="/booking?lang='+bookingLang+'"'),post.slug);
  assert.ok(page.includes('class="cta-primary" href="/booking?lang='+bookingLang+'"'),post.slug);
 }
});
