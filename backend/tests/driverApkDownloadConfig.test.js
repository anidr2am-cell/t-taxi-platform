const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..', '..');

test('production frontend serves APK from an external read-only directory', () => {
  const compose = fs.readFileSync(path.join(root, 'deploy', 'docker', 'docker-compose.production.yml'), 'utf8');
  const nginx = fs.readFileSync(path.join(root, 'deploy', 'docker', 'nginx.frontend.production.conf'), 'utf8');
  assert.match(compose, /\/srv\/tride\/downloads:\/usr\/share\/nginx\/html\/downloads:ro/);
  assert.match(nginx, /location = \/downloads\/driver-app\.apk/);
  assert.match(nginx, /application\/vnd\.android\.package-archive/);
  assert.match(nginx, /no-cache, must-revalidate/);
  assert.match(nginx, /location \/downloads\//);
});

test('APK publishing is outside Flutter web assets and service-worker cache', () => {
  const dockerfile = fs.readFileSync(path.join(root, 'deploy', 'docker', 'Dockerfile.frontend'), 'utf8');
  const worker = fs.readFileSync(path.join(root, 'deploy', 'docker', 'flutter_service_worker_cleanup.js'), 'utf8');
  const frontendWeb = path.join(root, 'frontend', 'web');
  assert.equal(fs.existsSync(path.join(frontendWeb, 'driver-app.apk')), false);
  assert.match(dockerfile, /cp \/tmp\/flutter_service_worker_cleanup\.js build\/web\/flutter_service_worker\.js/);
  assert.match(worker, /self\.registration\.unregister\(\)/);
});

test('download page and metadata expose release verification fields in Korean and Thai', () => {
  const html = fs.readFileSync(path.join(root, 'deploy', 'downloads', 'index.template.html'), 'utf8');
  const release = fs.readFileSync(path.join(root, 'deploy', 'downloads', 'release.template.json'), 'utf8');
  assert.match(html, /T-Rider 기사 앱/);
  assert.match(html, /แอปคนขับ T-Rider/);
  assert.match(html, /출처를 알 수 없는 앱 설치/);
  assert.match(html, /ติดตั้งแอปที่ไม่รู้จัก/);
  for (const marker of [
    '{{VERSION_NAME}}',
    '{{VERSION_CODE}}',
    '{{SHA256}}',
    '{{PUBLISHED_AT_DISPLAY}}',
  ]) {
    assert.match(html, new RegExp(marker.replace(/[{}]/g, '\\$&')));
  }
  assert.match(release, /signingCertificateSha256/);
  assert.match(release, /"publishedAt": "{{PUBLISHED_AT}}"/);
  const publishScript = fs.readFileSync(
    path.join(root, 'deploy', 'scripts', 'publish-driver-apk.ps1'),
    'utf8',
  );
  assert.match(publishScript, /ToString\('yyyy-MM-ddTHH:mm:sszzz'\)/);
  assert.match(publishScript, /ToString\('yyyy-MM-dd HH:mm'\)/);
});
