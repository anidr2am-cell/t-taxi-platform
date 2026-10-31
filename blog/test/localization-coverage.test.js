import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {execFileSync} from 'node:child_process';
import matter from 'gray-matter';
const root=path.resolve(import.meta.dirname,'../..');
const posts=fs.readdirSync(path.join(root,'blog/posts')).filter(f=>f.endsWith('.md')).map(f=>matter(fs.readFileSync(path.join(root,'blog/posts',f),'utf8')));
const out=fs.mkdtempSync(path.join(os.tmpdir(),'trider-localized-'));
execFileSync(process.execPath,['blog/build.js'],{cwd:root,env:{...process.env,BLOG_DIST_DIR:out}});
const read=slug=>fs.readFileSync(path.join(out,slug,'index.html'),'utf8');

test('every Korean topic has exactly one English, Japanese, Chinese and Russian translation with reciprocal links',()=>{
 const originals=posts.filter(p=>p.data.lang==='ko');
 assert.equal(originals.length,13);
 for(const original of originals){
  const key=original.data.translationKey;
  assert.ok(key,original.data.slug);
  for(const lang of ['en','ja','zh','ru']){
   const translations=posts.filter(p=>p.data.lang===lang&&p.data.translationKey===key);
   assert.equal(translations.length,1,`${key}: expected one ${lang} translation`);
   const post=translations[0];
   const html=read(post.data.slug);
   assert.ok(html.includes(`rel="canonical" href="https://trider.taxi/blog/${post.data.slug}"`));
   assert.ok(html.includes(`hreflang="ko" href="https://trider.taxi/blog/${original.data.slug}"`));
   assert.ok(read(original.data.slug).includes(`hreflang="${lang==='zh'?'zh-Hans':lang}" href="https://trider.taxi/blog/${post.data.slug}"`));
   for(const match of post.content.matchAll(/\]\(\/blog\/([a-z0-9-]+)\)/g)){
    const target=posts.find(p=>p.data.slug===match[1]);
    assert.ok(target,post.data.slug+': '+match[1]);
    assert.equal(target.data.lang,lang,post.data.slug+': mixed-language link');
   }
   for(const slug of post.data.related||[]){
    const target=posts.find(p=>p.data.slug===slug);
    assert.ok(target,post.data.slug+': missing related post '+slug);
    assert.equal(target.data.lang,lang,post.data.slug+': mixed-language related post');
   }
   const schemas=[...html.matchAll(/<script type="application\/ld\+json">([^<]+)<\/script>/g)].map(m=>JSON.parse(m[1]));
   assert.ok(schemas.some(s=>s['@type']==='Article'&&s.inLanguage===lang));
   assert.ok(html.includes(`href="/blog/lang/${lang}/"`));
  }
 }
});
test('Russian articles, lists and categories open the Russian customer booking form',()=>{
 const list=read('lang/ru');
 assert.ok(list.includes('Русский'));
 const russianPosts=posts.filter(p=>p.data.lang==='ru');
 const paths=[...russianPosts.map(p=>p.data.slug),'lang/ru',...['airport','golf','travel','faq'].map(c=>'lang/ru/category/'+c)];
 for(const pagePath of paths){
  const html=read(pagePath);
  assert.ok(html.includes('<html lang="ru">'));
  assert.ok(html.includes('Форма бронирования доступна на русском'));
  assert.ok(html.includes('Забронировать на русском'));
  assert.ok(html.includes('Язык общения с поддержкой уточняйте при обращении'));
  const links=[...html.matchAll(/href="(\/booking[^"\s]*)"/g)];
  assert.ok(links.length>0,pagePath);
  for(const [,href] of links)assert.equal(new URL(href.replaceAll('&amp;','&'),'https://trider.taxi').searchParams.get('lang'),'ru',pagePath);
  assert.doesNotMatch(html,/на английском|форма или сотрудники работают на русском языке/i);
 }
 for(const post of russianPosts)assert.ok(list.includes(`/blog/${post.data.slug}`));
 const faq=read('trider-airport-transfer-faq-ru');
 const schemas=[...faq.matchAll(/<script type="application\/ld\+json">([^<]+)<\/script>/g)].map(m=>JSON.parse(m[1]));
 const answer=schemas.find(s=>s['@type']==='FAQPage').mainEntity.find(q=>q.name==='Когда и на каком языке можно забронировать?')?.acceptedAnswer?.text;
 assert.ok(answer?.includes('на русском'), 'FAQ structured answer must agree with the Russian form');
 const sitemap=fs.readFileSync(path.join(out,'sitemap-blog.xml'),'utf8');
 for(const post of posts)assert.ok(sitemap.includes(`<loc>https://trider.taxi/blog/${post.data.slug}</loc>`));
 assert.ok(sitemap.includes('hreflang="ru"'));
 assert.ok(sitemap.includes('<loc>https://trider.taxi/blog/lang/ru/</loc>'));
});
test('new-language indexes lead with arrival and return transfer guides',()=>{
 for(const lang of ['zh','ja','ru']){
  const html=read(`lang/${lang}`);
  const cards=[...html.matchAll(/<article class="post-card">[\s\S]*?<h2><a href="\/blog\/([^"#]+)"/g)].map(m=>m[1]);
  assert.deepEqual(cards.slice(0,3),['suvarnabhumi-to-pattaya','don-mueang-to-pattaya','pattaya-to-airport-transfer'].map(s=>s+'-'+lang));
 }
});
test.after(()=>fs.rmSync(out,{recursive:true,force:true}));
