// QA-only: assert socket fixture seed left DB ready for contact-dispatch matrix (no secrets).
const assert = require('node:assert/strict');

assert.equal(process.env.DB_HOST, 'tride-qa-admin-db', 'wrong DB_HOST');
assert.equal(process.env.DB_NAME, 'tride_qa_admin', 'wrong DB_NAME');

const { createRequire } = require('node:module');
const requireBackend = createRequire(`${process.cwd()}/package.json`);
const { pool } = requireBackend('./src/config/database');
const fs = require('node:fs');

const FIXTURE_PATH = process.env.SOCKET_FIXTURE_PATH || '/srv/tride/backend/socket-fixture.json';

(async () => {
  assert.ok(fs.existsSync(FIXTURE_PATH), 'socket-fixture.json missing — run run-socket-fixture.cjs first');

  const [[userCount]] = await pool.query(
    'SELECT COUNT(*) AS c FROM users WHERE id IN (1, 2, 10, 11)',
  );
  assert.ok(Number(userCount.c) >= 4, `expected QA users 1,2,10,11 got count=${userCount.c}`);

  const [[driver11]] = await pool.query(
    'SELECT id FROM drivers WHERE id = 11 AND user_id = 11 AND is_active = 1 LIMIT 1',
  );
  assert.ok(driver11?.id, 'driver 11 not ready');

  const [[lineSetting]] = await pool.query(
    "SELECT 1 AS ok FROM settings WHERE group_name = 'contact_channels' AND key_name = 'contactLineEnabled' LIMIT 1",
  );
  assert.ok(lineSetting?.ok, 'contact LINE setting missing');

  const [[bands]] = await pool.query(
    'SELECT COUNT(*) AS c FROM city_transfer_distance_bands WHERE is_active = 1',
  );
  assert.ok(Number(bands.c) > 0, 'city_transfer_distance_bands missing');

  const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
  assert.equal(fixture.gate, true, 'fixture must be gate=true run');
  assert.equal(Number(fixture.socketDriverUserId), 11, 'fixture driver user 11');

  console.log(JSON.stringify({
    ok: true,
    validatedAt: new Date().toISOString(),
    gate: fixture.gate,
    socketDriverUserId: fixture.socketDriverUserId,
  }));
})().catch((err) => {
  console.error(JSON.stringify({ ok: false, error: err.message }));
  process.exitCode = 1;
}).finally(() => pool.end());
