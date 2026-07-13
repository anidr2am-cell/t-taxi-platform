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

test('production env validation rejects placeholder secrets and unsafe defaults', () => {
  const result = spawnSync(
    process.execPath,
    ['-e', "require('./src/config/env')"],
    {
      cwd: backendRoot,
      env: {
        ...process.env,
        NODE_ENV: 'production',
        DB_USER: 'tride_app',
        DB_NAME: 'tride_production',
        DB_PASSWORD: 'REPLACE_WITH_STRONG_PRODUCTION_DB_PASSWORD',
        JWT_ACCESS_SECRET: 'REPLACE_WITH_STRONG_RANDOM_ACCESS_SECRET_MIN_32_CHARS',
        JWT_REFRESH_SECRET: 'REPLACE_WITH_STRONG_RANDOM_REFRESH_SECRET_MIN_32_CHARS',
        CORS_ORIGIN: 'https://tride.example.com',
        ALLOW_DEV_QR_REISSUE: 'false',
      },
      encoding: 'utf8',
    },
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr + result.stdout, /placeholder value/);
  assert.match(result.stderr + result.stdout, /DB_HOST/);
  assert.match(result.stderr + result.stdout, /UPLOAD_DIR/);
  assert.match(result.stderr + result.stdout, /LOG_DIR/);
});

test('production env validation rejects example and placeholder secret markers', () => {
  const result = spawnSync(
    process.execPath,
    ['-e', "require('./src/config/env')"],
    {
      cwd: backendRoot,
      env: {
        ...process.env,
        NODE_ENV: 'production',
        DB_HOST: 'tride-prod-db',
        DB_USER: 'tride_app',
        DB_NAME: 'tride_production',
        DB_PASSWORD: 'EXAMPLE_PRODUCTION_DB_PASSWORD',
        JWT_ACCESS_SECRET: 'PLACEHOLDER_ACCESS_SECRET_VALUE',
        JWT_REFRESH_SECRET: 'CHANGE_ME_REFRESH_SECRET_VALUE',
        CORS_ORIGIN: 'https://tride.example.com',
        ALLOW_DEV_QR_REISSUE: 'false',
        UPLOAD_DIR: '/srv/tride/uploads',
        LOG_DIR: '/srv/tride/logs',
      },
      encoding: 'utf8',
    },
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr + result.stdout, /placeholder value/);
});

test('production env validation accepts explicit production-safe values', () => {
  const output = execFileSync(
    process.execPath,
    ['-e', "require('./src/config/env'); console.log('ok')"],
    {
      cwd: backendRoot,
      env: {
        ...process.env,
        NODE_ENV: 'production',
        DB_HOST: 'tride-prod-db',
        DB_USER: 'tride_app',
        DB_NAME: 'tride_production',
        DB_PASSWORD: 'strong-production-db-password',
        JWT_ACCESS_SECRET: 'strong-production-access-secret-value',
        JWT_REFRESH_SECRET: 'strong-production-refresh-secret-value',
        CORS_ORIGIN: 'https://tride.example.com',
        ALLOW_DEV_QR_REISSUE: 'false',
        UPLOAD_DIR: '/srv/tride/uploads',
        LOG_DIR: '/srv/tride/logs',
      },
      encoding: 'utf8',
    },
  );

  assert.match(output, /ok/);
});

test('Google Places key alias maps to backend Places provider config', () => {
  const output = execFileSync(
    process.execPath,
    ['-e', "const config=require('./src/config/env'); console.log(config.external.googleMapsApiKey)"],
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
        GOOGLE_MAPS_API_KEY: '',
        GOOGLE_PLACES_API_KEY: 'dummy-places-key',
      },
      encoding: 'utf8',
    },
  );

  assert.equal(output.trim(), 'dummy-places-key');
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

test('Linux migrate script exists and is documented', () => {
  const migrateSh = path.join(repoRoot, 'database', 'migrate.sh');
  assert.ok(fs.existsSync(migrateSh));
  const content = fs.readFileSync(migrateSh, 'utf8');
  assert.match(content, /migrate\.sh/);
  assert.match(content, /DB_NAME/);
});

test('.env.example contains placeholders only and staging-sensitive defaults are safe', () => {
  const envExample = fs.readFileSync(path.join(backendRoot, '.env.example'), 'utf8');
  const dockerEnvExample = fs.readFileSync(
    path.join(repoRoot, 'deploy', 'docker', '.env.example'),
    'utf8',
  );
  const productionDockerEnvExample = fs.readFileSync(
    path.join(repoRoot, 'deploy', 'docker', '.env.production.example'),
    'utf8',
  );

  assert.match(envExample, /FLIGHT_SYNC_ENABLED=false/);
  assert.match(envExample, /ALLOW_DEV_QR_REISSUE=false/);
  assert.match(dockerEnvExample, /GOOGLE_MAPS_API_KEY=/);
  assert.match(productionDockerEnvExample, /APP_ENV=production/);
  assert.doesNotMatch(envExample, /AIza[0-9A-Za-z_-]+/);
  assert.doesNotMatch(dockerEnvExample, /AIza[0-9A-Za-z_-]+/);
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

test('frontend Dockerfile requires explicit production API and socket build args', () => {
  const dockerfile = fs.readFileSync(
    path.join(repoRoot, 'deploy', 'docker', 'Dockerfile.frontend'),
    'utf8',
  );

  assert.match(dockerfile, /^ARG API_BASE_URL$/m);
  assert.match(dockerfile, /^ARG SOCKET_URL$/m);
  assert.doesNotMatch(dockerfile, /^ARG API_BASE_URL=http:\/\/localhost/m);
  assert.match(dockerfile, /API_BASE_URL is required when APP_ENV=production/);
  assert.match(dockerfile, /SOCKET_URL is required when APP_ENV=production/);
  assert.match(dockerfile, /EFFECTIVE_API_BASE_URL="\$\{API_BASE_URL:-http:\/\/localhost:3100\}"/);
});
