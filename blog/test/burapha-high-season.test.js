import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import matter from 'gray-matter';
test('Burapha planning guides distinguish verified vehicle fares from unverified green fees',()=>{
 for(const suffix of ['','-en','-ja','-zh','-ru']){
  const slug='burapha-cc-green-fee'+suffix;
  const {data,content}=matter(fs.readFileSync(new URL(`../posts/${slug}.md`,import.meta.url),'utf8'));
  assert.equal(new Date(data.updated).toISOString().slice(0,10),'2026-10-28',slug);
  assert.doesNotMatch(content,/2,?750|3,?150|2,?350|2,?650|5\s*%|band\.us\/@trounding/,slug);
  assert.match(content,/Buddy Golf|버디골프/,slug);
  for(const value of ['1,800','2,100','2,400','2,000','2,600','2,300','2,900'])assert.ok(content.includes(value),slug+': '+value);
 }
});
