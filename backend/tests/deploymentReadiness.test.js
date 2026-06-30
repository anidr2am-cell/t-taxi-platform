const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..', '..');
const backendRoot = path.resolve(__dirname, '..');

test('staging env validation accepts production-like safe placeholders only when strong values are provided', () => {
  const output = execFileSync(
    process.execPath,
    ['-e', "require('./src/config/env'); console.log('ok')"],
    {
      cwd: backendRoot,
      env: {
        ...process.env,
        NODE_ENV: 'staging',
        DB_USER: 'ttaxi_app',
        DB_NAME: 'ttaxi_staging',
        DB_PASSWORD: 'strong-db-password',
        JWT_ACCESS_SECRET: 'strong-access-secret-value',
        JWT_REFRESH_SECRET: 'strong-refresh-secret-value',
        CORS_ORIGIN: 'https://staging.example.com',
        ALLOW_DEV_QR_REISSUE: 'false',
      },
      encoding: 'utf8',
    },
  );

  assert.match(output, /ok/);
});

test('staging env validation rejects development QR reissue flag', () => {
  const result = spawnSync(
    process.execPath,
    ['-e', "require('./src/config/env')"],
    {
      cwd: backendRoot,
      env: {
        ...process.env,
        NODE_ENV: 'staging',
        DB_USER: 'ttaxi_app',
        DB_NAME: 'ttaxi_staging',
        DB_PASSWORD: 'strong-db-password',
        JWT_ACCESS_SECRET: 'strong-access-secret-value',
        JWT_REFRESH_SECRET: 'strong-refresh-secret-value',
        CORS_ORIGIN: 'https://staging.example.com',
        ALLOW_DEV_QR_REISSUE: 'true',
      },
      encoding: 'utf8',
    },
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr + result.stdout, /ALLOW_DEV_QR_REISSUE/);
});

test('migration validator prints deterministic order and duplicate prefix note', () => {
  const output = execFileSync(process.execPath, ['scripts/validate-migrations.js'], {
    cwd: backendRoot,
    encoding: 'utf8',
  });

  assert.match(output, /01\. 00_database\.sql/);
  assert.match(output, /21_flight_monitor\.sql/);
  assert.match(output, /21_notification_device_registration\.sql/);
  assert.match(output, /Duplicate numeric prefixes detected/);
});

test('PM2 config is parseable and uses one instance for worker safety', () => {
  const config = require(path.join(repoRoot, 'deploy', 'pm2', 'ecosystem.config.cjs'));

  assert.equal(config.apps.length, 1);
  assert.equal(config.apps[0].instances, 1);
  assert.equal(config.apps[0].exec_mode, 'fork');
  assert.equal(JSON.stringify(config).includes('replace-with'), false);
});

test('.env.example contains placeholders only and staging-sensitive defaults are safe', () => {
  const envExample = fs.readFileSync(path.join(backendRoot, '.env.example'), 'utf8');

  assert.match(envExample, /FLIGHT_SYNC_ENABLED=false/);
  assert.match(envExample, /ALLOW_DEV_QR_REISSUE=false/);
  assert.doesNotMatch(envExample, /AIza[0-9A-Za-z_-]+/);
  assert.doesNotMatch(envExample, /-----BEGIN PRIVATE KEY-----/);
  assert.doesNotMatch(envExample, /localhost:[0-9]+/);
});

test('staging smoke test refuses to run without explicit target URLs', () => {
  const result = spawnSync(process.execPath, ['scripts/staging-smoke-test.js'], {
    cwd: backendRoot,
    env: { ...process.env, STAGING_BASE_URL: '', STAGING_FRONTEND_URL: '' },
    encoding: 'utf8',
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr + result.stdout, /STAGING_BASE_URL/);
});
