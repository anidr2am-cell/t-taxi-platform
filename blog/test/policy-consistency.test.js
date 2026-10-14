import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import matter from 'gray-matter';

const postsDir = new URL('../posts/', import.meta.url);
const posts = fs.readdirSync(postsDir).filter(name => name.endsWith('.md')).map(name => ({
  name, ...matter(fs.readFileSync(new URL(name, postsDir), 'utf8')),
}));

test('all published languages omit unlimited waiting, unrestricted cancellation and vehicle capacities', () => {
  const forbidden = [
    /(?:대기|취소|환불)[^.\n]*(?:제한.{0,5}없|무제한)/,
    /no (?:waiting[ -]time limit|cancellation restrictions)|no restrictions on cancellations/i,
    /(?:待機時間|キャンセル|返金)[^。\n]*制限はありません/,
    /(?:等待时间|取消|退款)[^。\n]*没有限制/,
    /^\|[^\n]*(?:최대 인원|탑승 인원|이용 인원·짐|Passengers|Suitcases|定員|最多乘客|乘客与行李)[^\n]*\|$/im,
    /(?:최대\s*\d+명|carries up to \d+ passengers|Vehicle capacities are|定員はセダン\d|セダンは最大\d+人|轿车最多可乘坐\d|车辆容量为)/i,
    /(?<!\d)(?:550|1,100)(?!\d)/,
  ];
  for (const post of posts) {
    for (const pattern of forbidden) assert.doesNotMatch(post.content, pattern, post.name);
  }
});

test('changed FAQ policy answers also appear in the visible article in every existing language', () => {
  const faqs = posts.filter(p => p.data.translationKey === 'trider-airport-transfer-faq');
  assert.deepEqual(faqs.map(p => p.data.lang).sort(), ['en', 'ja', 'ko', 'zh']);
  for (const post of faqs) {
    for (const i of [0, 1, 2, 4, 5, 9]) {
      assert.ok(post.content.includes(post.data.faq[i].answer), `${post.name}: FAQ ${i + 1}`);
    }
    assert.match(post.data.faq[1].answer, /2/);
  }
});

test('TRounding price guarantees retain the explicit exclusion of TRider transfers', () => {
  const exclusion = {
    ko: '최저가 보장은 TRounding 판매 상품에 적용되며, TRider 이동 요금은 별도 정찰제입니다.',
    en: 'TRider transfers are not covered and have separate fixed fares.',
    ja: 'TRiderの送迎は価格保証の対象外で、別途定額料金となります。',
    zh: 'TRider接送不在保障范围内，采用独立固定价格。',
  };
  for (const post of posts.filter(p => /^(pattaya-golf-price-match-guarantee|trounding-golf-join-bar-benefits|burapha-cc-green-fee)/.test(p.name))) {
    assert.ok(post.content.includes(exclusion[post.data.lang]), post.name);
  }
});
