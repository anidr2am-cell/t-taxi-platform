const test = require('node:test');
const assert = require('node:assert/strict');

const { validateContactChannelUrl } = require('../src/utils/contactChannelUrl.util');

test('validateContactChannelUrl allows https URLs', () => {
  const result = validateContactChannelUrl('https://line.me/R/ti/p/@example');
  assert.equal(result.valid, true);
  assert.equal(result.scheme, 'https');
});

test('validateContactChannelUrl allows messenger custom schemes', () => {
  assert.equal(validateContactChannelUrl('line://ti/p/@example').valid, true);
  assert.equal(validateContactChannelUrl('kakaotalk://plusfriend/home/_abcd').valid, true);
  assert.equal(validateContactChannelUrl('whatsapp://send?phone=66123456789').valid, true);
});

test('validateContactChannelUrl rejects javascript URLs', () => {
  const result = validateContactChannelUrl('javascript:alert(1)');
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'blocked_scheme');
});

test('validateContactChannelUrl rejects data URLs', () => {
  const result = validateContactChannelUrl('data:text/html,hello');
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'blocked_scheme');
});

test('validateContactChannelUrl rejects malformed URLs', () => {
  const result = validateContactChannelUrl('not a url');
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'malformed');
});

test('validateContactChannelUrl rejects empty URLs', () => {
  const result = validateContactChannelUrl('   ');
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'empty');
});

test('validateContactChannelUrl rejects http in production mode', () => {
  const previous = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  const result = validateContactChannelUrl('http://example.com/add');
  process.env.NODE_ENV = previous;
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'http_not_allowed');
});
