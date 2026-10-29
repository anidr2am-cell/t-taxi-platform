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

test('golf guides provide shared consultation with LINE first for Japanese readers',()=>{
  for(const post of posts.filter(p=>p.data.category==='golf')){
    assert.ok(post.content.includes('https://wa.me/66815693445'),post.name);
    assert.doesNotMatch(post.content,/골프.{0,12}상담과.{0,12}차량.{0,12}별개|tour\/join consultation.*separate|相談と.*予約とは別|咨询与.*分别确认/i,post.name);
    if(post.data.lang==='ja'){
      assert.ok(post.content.includes('https://lin.ee/55A9phq'),post.name);
      assert.ok(post.content.indexOf('https://lin.ee/55A9phq')<post.content.indexOf('https://wa.me/66815693445'),post.name);
      assert.match(post.content,/まとめて相談/,post.name);
      assert.doesNotMatch(post.content,/主に韓国人|日本語[^。\n]*保証するものではありません/,post.name);
    }
  }
});

test('changed FAQ policy answers also appear in the visible article in every existing language', () => {
  const faqs = posts.filter(p => p.data.translationKey === 'trider-airport-transfer-faq');
  assert.deepEqual(faqs.map(p => p.data.lang).sort(), ['en', 'ja', 'ko', 'ru', 'zh']);
  for (const post of faqs) {
    for (const i of [0, 1, 2, 4, 5, 9]) {
      assert.ok(post.content.includes(post.data.faq[i].answer), `${post.name}: FAQ ${i + 1}`);
    }
    assert.match(post.data.faq[1].answer, /2/);
  }
});

test('golf copy omits unverified benefits, former contact links and price guarantees', () => {
  const golf = posts.filter(p => p.data.category === 'golf');
  for (const post of golf) {
    // Retained legacy URL paths are identifiers, not a price promise in visible copy.
    const publicCopy = [post.data.title, post.data.description, post.content.replace(/\]\([^)]+\)/g, ']')].join('\n');
    assert.doesNotMatch(publicCopy, /최저가|차액\s*환불|price[ -]match|price matching|refunds? the difference|価格保証|差額.{0,4}返金|价格保障|退还差价/i, post.name);
    assert.doesNotMatch(publicCopy, /무기한|유효기간.{0,6}없|no expiry|never expir|無期限|有効期限はありません|永久有效|没有有效期限制/i, post.name);
    assert.doesNotMatch(publicCopy, /11월\s*1일.{0,12}오픈|오픈.{0,12}11월\s*1일|opening.{0,12}November 1/i, post.name);
  }
  for (const post of golf.filter(p => /^(pattaya-golf-price-match-guarantee|trounding-golf-join-bar-benefits|burapha-cc-green-fee)/.test(p.name))) {
    assert.doesNotMatch(post.content, /5\s*%|band\.us\/@trounding/, post.name);
    assert.match(post.content, /버디골프|Buddy Golf/, post.name);
  }
});
