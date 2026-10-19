import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import matter from 'gray-matter';

const root = path.resolve(import.meta.dirname, '../..');
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'trider-burapha-high-season-'));
execFileSync(process.execPath, ['blog/build.js'], { cwd: root, env: { ...process.env, BLOG_DIST_DIR: output } });
const forbidden = /2,?350|2,?650|비수기|low[ -]season|ローシーズン|淡季|淡旺季/i;
const variants = [
  { suffix: '', note: '기준일 2026-10-17', sedan: '1인 이동비 900바트', suv: '1인 약 667바트', included: '캐디피·카트비', tips: '캐디팁이 포함되지 않습니다' },
  { suffix: '-en', note: 'Rates as of October 17, 2026', sedan: 'sedan costs THB 900 per person', suv: 'SUV costs about THB 667 each', included: 'Caddie fee and cart fee', tips: 'do not include caddie tips' },
  { suffix: '-ja', note: '2026年10月17日時点', sedan: '2人ならセダン', suv: 'SUVで1人約667バーツ', included: 'キャディフィー・カート代', tips: 'チップは含まれません' },
  { suffix: '-zh', note: '价格参考日期为2026年10月17日', sedan: '2人乘轿车', suv: '3人乘SUV，每人约667泰铢', included: '球童费、球车费', tips: '不包含球童小费' },
];

test('all four Burapha sources publish only confirmed high-season green fees', () => {
  for (const variant of variants) {
    const slug = 'burapha-cc-green-fee' + variant.suffix;
    const source = fs.readFileSync(path.join(root, 'blog/posts', slug + '.md'), 'utf8');
    const { data, content: rawContent } = matter(source); const content = rawContent.replaceAll(String.fromCharCode(13), "");
    assert.doesNotMatch(source, forbidden, slug);
    assert.equal(data.updated.toISOString().slice(0, 10), '2026-10-19', slug);
    const table = content.split('\n\n').find(block => block.startsWith('|'));
    assert.equal(table.split('\n').length, 3, slug);
    for (const value of ['2,750', '3,150', variant.included]) assert.ok(table.includes(value), slug + ': ' + value);
    for (const value of [variant.note, variant.sedan, variant.suv, variant.tips]) assert.ok(content.includes(value), slug + ': ' + value);
  }
});

test('published Burapha pages, titles and metadata contain no unconfirmed seasonal rates', () => {
  for (const { suffix } of variants) {
    const slug = 'burapha-cc-green-fee' + suffix;
    const html = fs.readFileSync(path.join(output, slug, 'index.html'), 'utf8');
    assert.doesNotMatch(html, forbidden, slug);
    assert.ok(html.includes('https://trider.taxi/blog/' + slug), slug);
    assert.ok(html.includes('2,750') && html.includes('3,150'), slug);
    assert.ok(html.includes('2026-10-19'), slug);
  }
});
test.after(() => fs.rmSync(output, { recursive: true, force: true }));


