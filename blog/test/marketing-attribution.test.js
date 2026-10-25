import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const source = fs.readFileSync(new URL('../assets/marketing-attribution.js', import.meta.url), 'utf8');
function page(href, { storage = new Map(), referrer = '', blocked = false } = {}) {
  const location = new URL(href), links = ['/booking?lang=en', '/blog/test', '/admin', 'https://band.us/@trounding']
    .map(href => ({ href: new URL(href, location).href }));
  const document = { referrer, querySelectorAll: () => links, addEventListener() {} };
  const window = {};
  vm.runInNewContext(source, {window, document, location, URL, URLSearchParams, Date,
    localStorage: {getItem: k => {if (blocked) throw Error('blocked'); return storage.get(k) ?? null;},
      setItem: (k,v) => storage.set(k,v), removeItem: k => storage.delete(k)}});
  return {api:window.trideMarketing, links, storage};
}
const first = 'tride_marketing_first_touch', last = 'tride_marketing_last_touch';
const campaign = '?utm_source=facebook&utm_medium=organic_social&utm_campaign=202611_golf_planning&utm_content=story_20261101&phone=private';

test('unknown consent carries safe post labels through language/blog/booking without storage', () => {
  const a = page('https://trider.taxi/' + campaign);
  assert.equal(a.storage.size, 0);
  const en = a.api.decorateUrl('/en/');
  assert.equal(new URL(en).searchParams.get('utm_content'), 'story_20261101');
  assert.equal(new URL(en).searchParams.has('phone'), false);
  const b = page(en, {storage:a.storage});
  const c = page(b.links[1].href, {storage:a.storage});
  assert.equal(new URL(c.links[0].href).searchParams.get('utm_source'), 'facebook');
  assert.equal(a.links[2].href, 'https://trider.taxi/admin');
  assert.equal(a.links[3].href, 'https://band.us/@trounding');
});

test('consent stores first and last content and survives reload and internal article UTM', () => {
  const storage = new Map([['tride_analytics_consent','granted']]);
  page('https://trider.taxi/' + campaign, {storage,referrer:'https://l.facebook.com/redirect?private=1'});
  const firstTouch = storage.get(first), lastTouch = storage.get(last);
  page('https://trider.taxi/blog/test?utm_source=blog&utm_content=internal', {storage,referrer:'https://trider.taxi/'});
  page('https://trider.taxi/booking', {storage,referrer:'https://trider.taxi/blog/test'});
  assert.equal(storage.get(first), firstTouch);
  assert.equal(storage.get(last), lastTouch);
  assert.equal(JSON.parse(lastTouch).referrer_host, 'l.facebook.com');
  const c = page('https://trider.taxi/en/', {storage});
  assert.equal(c.api.campaignParams().campaign_content, 'story_20261101');
  assert.equal(JSON.stringify(c.api.campaignParams()).includes('private'), false);
  page('https://trider.taxi/?utm_source=naver&utm_content=another_post', {storage});
  assert.equal(storage.get(first), firstTouch);
  assert.equal(JSON.parse(storage.get(last)).content, 'another_post');
});

test('denial clears records and removes labels from booking navigation', () => {
  const storage = new Map([['tride_analytics_consent','denied'],[first,'{}'],[last,'{}']]);
  const a = page('https://trider.taxi/' + campaign, {storage});
  assert.equal(storage.has(first), false);
  assert.equal(storage.has(last), false);
  assert.equal(new URL(a.links[0].href).searchParams.has('utm_source'), false);
  assert.equal(Object.keys(a.api.campaignParams()).length, 0);
});

test('blocked storage never breaks booking links; malformed/expired/staff records are replaced', () => {
  assert.doesNotThrow(() => page('https://trider.taxi/' + campaign, {blocked:true}));
  for (const old of ['broken', JSON.stringify({landing_page:'/admin',expires_at:'2099-01-01'}),
    JSON.stringify({landing_page:'/',expires_at:'2020-01-01'}), JSON.stringify({landing_page:'/',expires_at:'invalid'})]) {
    const storage = new Map([['tride_analytics_consent','granted'],[first,old],[last,old]]);
    page('https://trider.taxi/' + campaign, {storage});
    assert.equal(JSON.parse(storage.get(first)).content,'story_20261101');
  }
});

test('invalid labels are dropped and both generated surfaces load the same content-hashed script', () => {
  const a = page('https://trider.taxi/?utm_source=person%40example.com&utm_content=0812345678');
  assert.equal(new URL(a.links[0].href).searchParams.has('utm_source'),false);
  const root = new URL('../../', import.meta.url);
  assert.match(fs.readFileSync(new URL('landing/index.template.html',root),'utf8'), /\{\{ATTRIBUTION\}\}/);
  assert.match(fs.readFileSync(new URL('blog/build.js',root),'utf8'), /attributionAsset/);
});
