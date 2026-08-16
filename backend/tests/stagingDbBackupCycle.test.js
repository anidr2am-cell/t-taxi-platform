process.env.NODE_ENV = 'test';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');

const cycle = require('../scripts/stagingDbBackupCycle');

const scriptsDir = path.resolve(__dirname, '../scripts');
const backupCycleRunner = path.join(scriptsDir, 'run-staging-db-backup-cycle.sh');
const monthlyRunner = path.join(scriptsDir, 'run-staging-db-monthly-rehearsal.sh');
const remoteRunner = path.join(scriptsDir, 'staging-db-backup-remote.sh');
const pruneRunner = path.join(scriptsDir, 'prune-staging-db-backups.sh');
const envExample = path.resolve(__dirname, '../../deploy/docker/.env.backup.example');
const backupService = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-backup.service');
const backupTimer = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-backup.timer');
const rehearsalService = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-rehearsal.service');
const rehearsalTimer = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-rehearsal.timer');

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function makeBackupPair(root, timestamp, size = 100) {
  const filename = `tride_staging-${timestamp}.sql.gz`;
  const backupPath = path.join(root, filename);
  const manifestPath = path.join(root, `${filename.slice(0, -7)}.manifest`);
  fs.writeFileSync(backupPath, 'x'.repeat(size));
  fs.writeFileSync(manifestPath, [
    `BACKUP_SHA256=abc123`,
    `BACKUP_SIZE_BYTES=${size}`,
  ].join('\n'));
  return { filename, backupPath, manifestPath };
}

test('parseBackupConfig defaults remote and auto prune to disabled', () => {
  const config = cycle.parseBackupConfig({});
  assert.equal(config.remoteEnabled, false);
  assert.equal(config.autoPrune, false);
});

test('remote enabled mode rejects missing remote config', () => {
  assert.throws(
    () => cycle.assertRemoteConfigWhenEnabled(cycle.parseBackupConfig({
      TRIDE_BACKUP_REMOTE_ENABLED: '1',
    })),
    /TRIDE_BACKUP_REMOTE_NAME/,
  );
});

test('evaluatePruneGate blocks prune when remote disabled or failed', () => {
  assert.equal(cycle.evaluatePruneGate({
    BACKUP_RESULT: 'PASS',
    REMOTE_COPY_RESULT: 'SKIPPED_DISABLED',
    REMOTE_VERIFY_RESULT: 'SKIPPED_DISABLED',
    autoPrune: true,
  }).allowed, false);

  assert.equal(cycle.evaluatePruneGate({
    BACKUP_RESULT: 'PASS',
    REMOTE_COPY_RESULT: 'FAIL',
    REMOTE_VERIFY_RESULT: 'FAIL',
    autoPrune: true,
  }).allowed, false);

  assert.equal(cycle.evaluatePruneGate({
    BACKUP_RESULT: 'PASS',
    REMOTE_COPY_RESULT: 'PASS',
    REMOTE_VERIFY_RESULT: 'PASS',
    autoPrune: false,
  }).allowed, false);

  assert.equal(cycle.evaluatePruneGate({
    BACKUP_RESULT: 'PASS',
    REMOTE_COPY_RESULT: 'PASS',
    REMOTE_VERIFY_RESULT: 'PASS',
    autoPrune: true,
  }).allowed, true);
});

test('retention keeps newest and applies 14 daily 8 weekly 6 monthly buckets', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-'));
  const stamps = [
    '20260816-120000',
    '20260815-120000',
    '20260814-120000',
    '20260807-120000',
    '20260716-120000',
    '20260316-120000',
  ];
  for (const stamp of stamps) {
    makeBackupPair(root, stamp);
  }
  const inventory = cycle.inventoryBackups(root);
  assert.equal(inventory.entries.length, stamps.length);
  const plan = cycle.classifyRetention(inventory);
  assert.ok(plan.keep.includes('tride_staging-20260816-120000.sql.gz'));
  assert.equal(plan.keep.length, plan.keep.filter((value, index, arr) => arr.indexOf(value) === index).length);
});

test('retention ignores malformed filenames and orphan pairs', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-'));
  makeBackupPair(root, '20260816-120000');
  fs.writeFileSync(path.join(root, 'bad-name.sql.gz'), 'data');
  fs.writeFileSync(path.join(root, 'tride_staging-20260815-120000.sql.gz'), 'orphan');
  fs.writeFileSync(path.join(root, 'orphan.manifest'), 'BACKUP_SHA256=x');
  const inventory = cycle.inventoryBackups(root);
  assert.equal(inventory.entries.length, 1);
  assert.deepEqual(inventory.malformed, ['bad-name.sql.gz']);
  assert.deepEqual(inventory.orphanBackups, ['tride_staging-20260815-120000.sql.gz']);
  assert.deepEqual(inventory.orphanManifests, ['orphan.manifest']);
});

test('buildRemoteObjectPrefix preserves date hierarchy without secrets', () => {
  const remote = cycle.buildRemoteObjectPrefix(
    'tride_staging-20260816-155810.sql.gz',
    'T-Rider',
  );
  assert.equal(remote.remoteDir, 'T-Rider/staging/db/2026/08');
  assert.equal(remote.backupObject, 'T-Rider/staging/db/2026/08/tride_staging-20260816-155810.sql.gz');
  assert.equal(remote.manifestObject, 'T-Rider/staging/db/2026/08/tride_staging-20260816-155810.manifest');
});

test('daily cycle runner enforces backup before remote and gated prune', () => {
  const contents = read(backupCycleRunner);
  assert.match(contents, /flock -n 9/);
  assert.match(contents, /run-staging-db-backup\.sh/);
  assert.match(contents, /staging-db-backup-remote\.sh/);
  assert.match(contents, /LOCAL_PRUNE_RUN=\$\{LOCAL_PRUNE_RUN\}/);
  assert.match(contents, /LOCAL_PRUNE_RUN="NO"/);
  assert.match(contents, /"\$\{REMOTE_COPY_RESULT\}" == "PASS"/);
  assert.match(contents, /TRIDE_BACKUP_AUTO_PRUNE/);
  assert.doesNotMatch(contents, /docker system prune/);
  assert.doesNotMatch(contents, /\/opt\/ktaxi/);
});

test('remote runner supports disabled mode and verifies both files when enabled', () => {
  const contents = read(remoteRunner);
  assert.match(contents, /REMOTE_COPY_RESULT=SKIPPED_DISABLED/);
  assert.match(contents, /rclone copyto/);
  assert.match(contents, /REMOTE_VERIFY_RESULT=PASS/);
  assert.doesNotMatch(contents, /echo.*PASSWORD/i);
  assert.doesNotMatch(contents, /AWS_SECRET/);
});

test('prune runner defaults to dry-run and requires node retention planner', () => {
  const contents = read(pruneRunner);
  assert.match(contents, /staging-db-backup-retention-plan\.js/);
  assert.match(contents, /--apply/);
  assert.doesNotMatch(contents, /date -d '14 days ago'/);
});

test('monthly rehearsal uses latest complete pair and isolated restore runner', () => {
  const contents = read(monthlyRunner);
  assert.match(contents, /--select-latest/);
  assert.match(contents, /run-staging-db-restore-rehearsal\.sh/);
  assert.match(contents, /172\.18\.0\.1:3100\/api\/v1\/health/);
  assert.match(contents, /https:\/\/trider\.taxi\/api\/v1\/health/);
  assert.doesNotMatch(contents, /docker exec tride-db/);
});

test('systemd units reference T-Rider scripts only', () => {
  for (const file of [backupService, rehearsalService]) {
    const contents = read(file);
    assert.match(contents, /\/opt\/t-ride/);
    assert.doesNotMatch(contents, /\/opt\/ktaxi/);
    assert.doesNotMatch(contents, /ktaxi/);
    assert.doesNotMatch(contents, /docker compose down/);
    assert.doesNotMatch(contents, /docker system prune/);
  }
  for (const file of [backupTimer, rehearsalTimer]) {
    const contents = read(file);
    assert.match(contents, /Persistent=true/);
    assert.match(contents, /Timezone=Asia\/Bangkok/);
    assert.doesNotMatch(contents, /\/opt\/ktaxi/);
  }
});

test('env backup example contains placeholders only', () => {
  const contents = read(envExample);
  assert.match(contents, /TRIDE_BACKUP_REMOTE_ENABLED=0/);
  assert.match(contents, /TRIDE_BACKUP_AUTO_PRUNE=0/);
  assert.equal(cycle.envExampleContainsSecrets(contents), false);
});

test('structured log builder omits secret-like fields', () => {
  const entry = cycle.buildStructuredLogEntry({
    BACKUP_RESULT: 'PASS',
    BACKUP_FILE: '/opt/t-ride/backups/tride_staging-20260816.sql.gz',
    DB_PASSWORD: 'hidden',
    REMOTE_COPY_RESULT: 'SKIPPED_DISABLED',
  });
  assert.equal(entry.BACKUP_RESULT, 'PASS');
  assert.equal(entry.DB_PASSWORD, undefined);
});

test('findLatestCompleteBackup selects newest valid pair', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-'));
  makeBackupPair(root, '20260815-120000');
  makeBackupPair(root, '20260816-120000');
  const latest = cycle.findLatestCompleteBackup(cycle.inventoryBackups(root));
  assert.equal(latest.filename, 'tride_staging-20260816-120000.sql.gz');
});
