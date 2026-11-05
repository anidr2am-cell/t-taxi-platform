const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
test('release image forwards public Firebase configuration to both Flutter build branches', () => {
  const docker = fs.readFileSync(path.join(root, 'deploy/docker/Dockerfile.frontend'), 'utf8');
  const compose = fs.readFileSync(path.join(root, 'deploy/docker/docker-compose.production.yml'), 'utf8');
  for (const key of ['API_KEY','APP_ID','MESSAGING_SENDER_ID','PROJECT_ID','AUTH_DOMAIN','STORAGE_BUCKET','VAPID_KEY']) {
    assert(docker.includes(`ARG FIREBASE_${key}`));
    assert.equal(docker.split(`--dart-define="FIREBASE_${key}=`).length - 1, 2, key);
    assert(compose.includes(`FIREBASE_${key}: \${FIREBASE_WEB_${key}:-}`), key);
  }
  assert.doesNotMatch(docker, /dart-define=.*(?:PRIVATE_KEY|SERVICE_ACCOUNT)/);
});
test('preview public configuration rejects service-account fields and mobile app identifiers', () => {
  const script = fs.readFileSync(path.join(root, 'deploy/scripts/build-frontend-preview.ps1'), 'utf8');
  assert.match(script, /Only public Firebase web fields are allowed/);
  assert.match(script, /appId -notmatch ':web:'/);
  assert.match(script, /vapidKey -notmatch/);
});
