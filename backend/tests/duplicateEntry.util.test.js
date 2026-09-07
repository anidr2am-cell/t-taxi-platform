const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  isDuplicatePhoneEntry,
  isDuplicateEmailEntry,
} = require('../src/utils/duplicateEntry.util');

test('isDuplicatePhoneEntry detects uk_users_phone constraint violations', () => {
  const err = new Error('Duplicate entry');
  err.code = 'ER_DUP_ENTRY';
  err.sqlMessage = "Duplicate entry '+821012345678' for key 'uk_users_phone'";

  assert.equal(isDuplicatePhoneEntry(err), true);
  assert.equal(isDuplicateEmailEntry(err), false);
});

test('isDuplicateEmailEntry detects email_active constraint violations', () => {
  const err = new Error('Duplicate entry');
  err.code = 'ER_DUP_ENTRY';
  err.sqlMessage = "Duplicate entry 'user@test.local' for key 'uk_users_email_active'";

  assert.equal(isDuplicateEmailEntry(err), true);
  assert.equal(isDuplicatePhoneEntry(err), false);
});
