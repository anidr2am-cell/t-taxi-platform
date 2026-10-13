const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('all download locations send no-store even for 404 responses', () => {
  const config = fs.readFileSync(path.join(__dirname, '../../deploy/docker/nginx.frontend.production.conf'), 'utf8');
  const downloads = config.slice(config.indexOf('    location = /downloads/driver-app.apk'), config.indexOf('    location = /index.html'));
  assert.equal((downloads.match(/add_header Cache-Control "no-store" always;/g) || []).length, 3);
  assert.match(downloads, /add_header Content-Disposition 'attachment; filename="TRider-Driver.apk"' always;/);
});

test('the existing five CI jobs run for both PRs and main pushes', () => {
  const workflow = fs.readFileSync(path.join(__dirname, '../../.github/workflows/pr-checks.yml'), 'utf8');
  assert.match(workflow, /push:\s*\n\s*branches: \[main\]/);
  assert.match(workflow, /pull_request:/);
  for (const name of ['Static blog build', 'Backend tests', 'Frontend Flutter tests', 'Driver app Flutter tests', 'Frontend web build']) {
    assert.ok(workflow.includes(`name: ${name}`), name);
  }
});
