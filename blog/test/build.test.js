import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const dist = path.join(root, 'blog', 'dist');

test('blog build emits crawlable pages and SEO metadata', () => {
  execFileSync(process.execPath, ['blog/build.js'], { cwd: root });
  const html = fs.readFileSync(path.join(dist, 'suvarnabhumi-to-pattaya', 'index.html'), 'utf8');
  assert.match(html, /<html lang="ko">/);
  assert.match(html, /<title>수완나품 공항에서 파타야 가는 법 총정리/);
  assert.match(html, /name="description"/);
  assert.match(html, /rel="canonical" href="https:\/\/trider\.taxi\/blog\/suvarnabhumi-to-pattaya"/);
  assert.match(html, /application\/ld\+json/);
  assert.match(html, /"@type":"Article"/);
  assert.match(html, /최종 업데이트:.*2026-10-01/s);
  assert.match(html, /세단 1,000바트|1,000바트/);
  assert.match(html, /href="https:\/\/trider\.taxi\/">지금 예약하기<\/a>/);
  assert.match(html, /href="https:\/\/open\.kakao\.com\/o\/suG4krMi"/);
  assert.doesNotMatch(html, /flutter_bootstrap|serviceWorker/);
});

test('blog build emits lists, categories, and standalone sitemap', () => {
  assert.ok(fs.existsSync(path.join(dist, 'index.html')));
  assert.ok(fs.existsSync(path.join(dist, 'category', 'airport', 'index.html')));
  const sitemap = fs.readFileSync(path.join(dist, 'sitemap-blog.xml'), 'utf8');
  assert.match(sitemap, /https:\/\/trider\.taxi\/blog\/suvarnabhumi-to-pattaya/);
});
