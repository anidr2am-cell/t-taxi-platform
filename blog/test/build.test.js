import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
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
  assert.match(html, /property="og:image" content="https:\/\/trider\.taxi\/blog\/assets\/og-default\.png"/);
  assert.doesNotMatch(html, /flutter_bootstrap|serviceWorker/);
  const defaultOg = fs.readFileSync(path.join(root, 'blog', 'assets', 'og-default.png'));
  assert.equal(defaultOg.readUInt32BE(16), 1200);
  assert.equal(defaultOg.readUInt32BE(20), 630);
});

test('blog build emits lists, categories, and standalone sitemap', () => {
  assert.ok(fs.existsSync(path.join(dist, 'index.html')));
  assert.ok(fs.existsSync(path.join(dist, 'category', 'airport', 'index.html')));
  const sitemap = fs.readFileSync(path.join(dist, 'sitemap-blog.xml'), 'utf8');
  assert.match(sitemap, /https:\/\/trider\.taxi\/blog\/suvarnabhumi-to-pattaya/);
  assert.match(sitemap, /<loc>https:\/\/trider\.taxi\/blog\/suvarnabhumi-to-pattaya<\/loc><lastmod>2026-10-01<\/lastmod>/);
  assert.match(sitemap, /<loc>https:\/\/trider\.taxi\/blog\/<\/loc><lastmod>2026-10-01<\/lastmod>/);
  assert.doesNotMatch(sitemap, /<url><loc>[^<]+<\/loc><\/url>/);
});

test('multilingual build emits alternates, localized CTAs, related posts, and valid JSON-LD', () => {
  const fixtureDist = fs.mkdtempSync(path.join(os.tmpdir(), 'trider-blog-test-'));
  try {
    execFileSync(process.execPath, ['blog/build.js'], {
      cwd: root,
      env: {
        ...process.env,
        BLOG_POSTS_DIR: path.join(root, 'blog', 'test', 'fixtures', 'posts'),
        BLOG_DIST_DIR: fixtureDist,
      },
    });
    const readPage = (slug) => fs.readFileSync(path.join(fixtureDist, slug, 'index.html'), 'utf8');
    const ko = readPage('fixture-guide');
    const en = readPage('fixture-guide-en');
    const ja = readPage('fixture-guide-ja');
    const zh = readPage('fixture-guide-zh');

    for (const html of [ko, en, ja, zh]) {
      assert.match(html, /hreflang="ko" href="https:\/\/trider\.taxi\/blog\/fixture-guide"/);
      assert.match(html, /hreflang="en" href="https:\/\/trider\.taxi\/blog\/fixture-guide-en"/);
      assert.match(html, /hreflang="ja" href="https:\/\/trider\.taxi\/blog\/fixture-guide-ja"/);
      assert.match(html, /hreflang="zh-Hans" href="https:\/\/trider\.taxi\/blog\/fixture-guide-zh"/);
      assert.match(html, /hreflang="x-default" href="https:\/\/trider\.taxi\/blog\/fixture-guide"/);
      const scripts = [...html.matchAll(/<script type="application\/ld\+json">([^<]+)<\/script>/g)];
      assert.ok(scripts.length >= 2);
      const objects = scripts.map((match) => JSON.parse(match[1]));
      const expectedLanguage = { ko: 'ko', en: 'en', ja: 'ja', zh: 'zh' }[
        html.match(/<html lang="([^"]+)"/)?.[1]
      ];
      assert.ok(objects.some((item) => item['@type'] === 'Article' && item.inLanguage === expectedLanguage));
      assert.ok(objects.some((item) => item['@type'] === 'BreadcrumbList'));
    }

    assert.match(ko, /카카오톡 상담/);
    assert.match(ko, /https:\/\/open\.kakao\.com\/o\/suG4krMi/);
    assert.match(en, /Fixed-price airport transfers · Book 24\/7/);
    assert.match(en, /https:\/\/wa\.me\/66815693445/);
    const englishList = fs.readFileSync(path.join(fixtureDist, 'lang', 'en', 'index.html'), 'utf8');
    assert.match(englishList, /<p class="eyebrow">Airport<\/p>/);
    assert.match(englishList, /Last updated:/);
    assert.match(ja, /定額の空港送迎・24時間予約/);
    assert.match(ja, /https:\/\/lin\.ee\/55A9phq/);
    assert.match(zh, /固定价格机场接送 · 24小时预约/);
    assert.match(zh, /https:\/\/wa\.me\/66815693445/);

    const related = en.match(/<aside class="related">([\s\S]+?)<\/aside>/)?.[1] || '';
    assert.match(related, /fixture-related-en/);
    assert.doesNotMatch(related, /href="\/blog\/fixture-guide-en"/);

    const sitemap = fs.readFileSync(path.join(fixtureDist, 'sitemap-blog.xml'), 'utf8');
    assert.match(sitemap, /xmlns:xhtml="http:\/\/www\.w3\.org\/1999\/xhtml"/);
    assert.match(sitemap, /<lastmod>2026-10-03<\/lastmod>/);
    assert.match(sitemap, /xhtml:link rel="alternate" hreflang="zh-Hans" href="https:\/\/trider\.taxi\/blog\/fixture-guide-zh"/);
    assert.ok(fs.existsSync(path.join(fixtureDist, 'lang', 'en', 'index.html')));
    assert.ok(fs.existsSync(path.join(fixtureDist, 'lang', 'ja', 'category', 'airport', 'index.html')));
  } finally {
    fs.rmSync(fixtureDist, { recursive: true, force: true });
  }
});
