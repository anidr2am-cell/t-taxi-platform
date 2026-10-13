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
  assert.match(html, /driver-app\.apk\?v=\{\{VERSION_CODE\}\}/);
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
  assert.match(publishScript, /Replace\("`r`n", "`n"\)/);
});

test('driver release build is pinned to the production flavor and entrypoint', () => {
  const buildScript = fs.readFileSync(
    path.join(root, 'driver_app', 'scripts', 'build-release-apk.ps1'),
    'utf8',
  );
  assert.match(buildScript, /flutter build apk --release --flavor prod -t lib\/main_prod\.dart/);
  assert.match(buildScript, /verify-release-apk\.ps1/);
  assert.match(buildScript, /app-prod-release\.apk[\s\S]+Remove-Item/);
  assert.doesNotMatch(buildScript, /\[string\]\$Flavor|\[string\]\$Target/);
});

test('build and publish share endpoint, package, version and signer verification', () => {
  const verifier = fs.readFileSync(
    path.join(root, 'driver_app', 'scripts', 'verify-release-apk.ps1'),
    'utf8',
  );
  const publishScript = fs.readFileSync(
    path.join(root, 'deploy', 'scripts', 'publish-driver-apk.ps1'),
    'utf8',
  );
  assert.match(verifier, /com\.trider\.driver/);
  assert.match(verifier, /https:\/\/trider\.taxi/);
  for (const forbidden of ['10.0.2.2', 'localhost', '127.0.0.1', '103.60.127.213', 'taxi.kecosystem.com', '159.89.192.55']) {
    assert.match(verifier, new RegExp(forbidden.replaceAll('.', '\\.')));
  }
  assert.match(verifier, /versionCode[^\n]+greater than published versionCode/);
  assert.match(publishScript, /verify-release-apk\.ps1/);
  assert.match(publishScript, /downloads-backup/);
  assert.match(publishScript, /ln '\$RemoteDirectory\/driver-app\.apk' '\$backupDirectory\/driver-app\.apk'/);
  assert.match(publishScript, /mv -f '\$RemoteDirectory\/driver-app\.apk\.part' '\$RemoteDirectory\/driver-app\.apk'/);
});
