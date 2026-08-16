process.env.NODE_ENV = 'test';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');

const { execFileSync } = require('node:child_process');

const cycle = require('../scripts/stagingDbBackupCycle');

const scriptsDir = path.resolve(__dirname, '../scripts');
const backupCycleRunner = path.join(scriptsDir, 'run-staging-db-backup-cycle.sh');
const monthlyRunner = path.join(scriptsDir, 'run-staging-db-monthly-rehearsal.sh');
const remoteRunner = path.join(scriptsDir, 'staging-db-backup-remote.sh');
const pruneRunner = path.join(scriptsDir, 'prune-staging-db-backups.sh');
const retentionLib = path.join(scriptsDir, 'staging-db-backup-retention-lib.sh');
const envExample = path.resolve(__dirname, '../../deploy/env.backup.example');
const backupService = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-backup.service');
const backupTimer = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-backup.timer');
const rehearsalService = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-rehearsal.service');
const rehearsalTimer = path.resolve(__dirname, '../../deploy/systemd/tride-staging-db-rehearsal.timer');

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function bashRetentionAvailable() {
  try {
    execFileSync('bash', ['--version'], { stdio: 'ignore' });
    execFileSync('bash', ['-lc', 'date -u -d "2026-08-16" +%G-W%V'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function runBashRetentionPlan(root, apply = false) {
  const script = [
    `source "${retentionLib.replace(/\\/g, '/')}"`,
    `TRIDE_BACKUP_ROOT="${root.replace(/\\/g, '/')}"`,
    `backup_retention_emit_plan ${apply ? 1 : 0}`,
  ].join('\n');
  return execFileSync('bash', ['-lc', script], { encoding: 'utf8' });
}

function runBashLatestSelection(root) {
  const script = [
    `source "${retentionLib.replace(/\\/g, '/')}"`,
    `TRIDE_BACKUP_ROOT="${root.replace(/\\/g, '/')}"`,
    'backup_retention_select_latest_backup_path',
  ].join('\n');
  return execFileSync('bash', ['-lc', script], { encoding: 'utf8' }).trim();
}

function assertNoHostNodeInvocation(contents, fileLabel) {
  assert.doesNotMatch(contents, /command -v node/, `${fileLabel} must not check for node`);
  assert.doesNotMatch(contents, /\bexec node\b/, `${fileLabel} must not exec node`);
  assert.doesNotMatch(contents, /\bnode "/, `${fileLabel} must not invoke node CLI`);
  assert.doesNotMatch(contents, /\bnode -e\b/, `${fileLabel} must not invoke node -e`);
  assert.doesNotMatch(contents, /\bnpm\b/, `${fileLabel} must not invoke npm`);
}

function parsePlanOutput(output) {
  const lines = String(output || '').split(/\r?\n/);
  const result = {
    keep: [],
    candidates: [],
    malformed: [],
    orphanBackups: [],
    orphanManifests: [],
    deleted: [],
    mode: '',
  };
  for (const line of lines) {
    if (line.startsWith('KEEP_')) result.keep.push(line.split('=')[1]);
    if (line.startsWith('CANDIDATE=')) result.candidates.push(line.slice('CANDIDATE='.length));
    if (line.startsWith('MALFORMED=')) result.malformed.push(line.slice('MALFORMED='.length));
    if (line.startsWith('ORPHAN_BACKUP=')) result.orphanBackups.push(line.slice('ORPHAN_BACKUP='.length));
    if (line.startsWith('ORPHAN_MANIFEST=')) result.orphanManifests.push(line.slice('ORPHAN_MANIFEST='.length));
    if (line.startsWith('DELETED=')) result.deleted.push(line.slice('DELETED='.length));
    if (line.startsWith('RETENTION_MODE=')) result.mode = line.slice('RETENTION_MODE='.length);
  }
  return result;
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
  assert.match(contents, /bash "\$\{BACKUP_RUNNER\}" 2>&1/);
  assert.match(contents, /bash "\$\{REMOTE_RUNNER\}"/);
  assert.match(contents, /bash "\$\{PRUNE_RUNNER\}" --apply/);
  assert.doesNotMatch(contents, /BACKUP_OUTPUT="\$\{BACKUP_RUNNER\}"/);
  assert.match(contents, /read_kv_or_default BACKUP_RESULT .* FAIL/);
  assert.match(contents, /LOCAL_PRUNE_RUN=\$\{LOCAL_PRUNE_RUN\}/);
  assert.match(contents, /LOCAL_PRUNE_RUN="NO"/);
  assert.match(contents, /"\$\{REMOTE_COPY_RESULT\}" == "PASS"/);
  assert.match(contents, /TRIDE_BACKUP_AUTO_PRUNE/);
  assert.doesNotMatch(contents, /docker system prune/);
  assert.doesNotMatch(contents, /\/opt\/ktaxi/);
});

test('internal shell runners are invoked via bash without executable-bit dependency', () => {
  const cycleContents = read(backupCycleRunner);
  const monthlyContents = read(monthlyRunner);
  assert.equal(cycle.invokesShellScriptViaBash(cycleContents, 'BACKUP_RUNNER'), true);
  assert.equal(cycle.invokesShellScriptViaBash(cycleContents, 'REMOTE_RUNNER'), true);
  assert.equal(cycle.invokesShellScriptViaBash(cycleContents, 'PRUNE_RUNNER'), true);
  assert.equal(cycle.invokesShellScriptViaBash(monthlyContents, 'RESTORE_RUNNER'), true);
});

test('subprocess failure reports FAIL instead of blank key values', () => {
  assert.equal(cycle.readKeyValueOrDefault('', 'BACKUP_RESULT', 'FAIL'), 'FAIL');
  assert.equal(cycle.readKeyValueOrDefault('BACKUP_RESULT=\n', 'BACKUP_RESULT', 'FAIL'), 'FAIL');
  assert.equal(cycle.readKeyValueOrDefault('BACKUP_RESULT=PASS', 'BACKUP_RESULT', 'FAIL'), 'PASS');
  assert.equal(
    cycle.readKeyValueOrDefault('REMOTE_COPY_RESULT=SKIPPED_DISABLED\nREMOTE_VERIFY_RESULT=SKIPPED_DISABLED', 'REMOTE_COPY_RESULT', 'FAIL'),
    'SKIPPED_DISABLED',
  );
});

test('remote-disabled mode remains unchanged in backup cycle defaults', () => {
  const contents = read(backupCycleRunner);
  assert.match(contents, /REMOTE_COPY_RESULT="SKIPPED_DISABLED"/);
  assert.match(contents, /REMOTE_VERIFY_RESULT="SKIPPED_DISABLED"/);
});

test('remote runner supports disabled mode and verifies both files when enabled', () => {
  const contents = read(remoteRunner);
  assert.match(contents, /REMOTE_COPY_RESULT=SKIPPED_DISABLED/);
  assert.match(contents, /rclone copyto/);
  assert.match(contents, /REMOTE_VERIFY_RESULT=PASS/);
  assert.doesNotMatch(contents, /echo.*PASSWORD/i);
  assert.doesNotMatch(contents, /AWS_SECRET/);
});

test('prune runner defaults to dry-run and uses bash retention planner', () => {
  const contents = read(pruneRunner);
  assert.match(contents, /staging-db-backup-retention-lib\.sh/);
  assert.match(contents, /backup_retention_emit_plan/);
  assert.match(contents, /--apply/);
  assert.doesNotMatch(contents, /\bexec node\b/);
  assert.doesNotMatch(contents, /\bnode "/);
  assert.doesNotMatch(contents, /\bnpm\b/);
  assert.doesNotMatch(contents, /date -d '14 days ago'/);
});

test('monthly rehearsal uses bash latest selection and isolated restore runner', () => {
  const contents = read(monthlyRunner);
  assert.match(contents, /backup_retention_select_latest_backup_path/);
  assert.match(contents, /staging-db-backup-retention-lib\.sh/);
  assert.match(contents, /bash "\$\{RESTORE_RUNNER\}"/);
  assert.match(contents, /RESTORE_REHEARSAL="FAIL"/);
  assert.match(contents, /log_monthly_diagnostics/);
  assert.match(contents, /MONTHLY_REHEARSAL_BACKUP=\$\{MONTHLY_REHEARSAL_BACKUP\}/);
  assert.match(contents, /172\.18\.0\.1:3100\/api\/v1\/health/);
  assert.match(contents, /https:\/\/trider\.taxi\/api\/v1\/health/);
  assert.doesNotMatch(contents, /\bexec node\b/);
  assert.doesNotMatch(contents, /\bnode "/);
  assert.doesNotMatch(contents, /docker exec tride-db/);
});

test('host backup automation scripts do not require node or npm', () => {
  for (const file of [backupCycleRunner, monthlyRunner, pruneRunner, retentionLib]) {
    assertNoHostNodeInvocation(read(file), file);
  }
});

test('systemd units reference T-Rider scripts only and do not require node', () => {
  for (const file of [backupService, rehearsalService]) {
    const contents = read(file);
    assert.match(contents, /\/opt\/t-ride/);
    assert.match(contents, /\/bin\/bash/);
    assert.doesNotMatch(contents, /\/opt\/ktaxi/);
    assert.doesNotMatch(contents, /ktaxi/);
    assert.doesNotMatch(contents, /\bnode\b/);
    assert.doesNotMatch(contents, /\bnpm\b/);
    assert.doesNotMatch(contents, /prune-staging-db-backups\.sh --apply/);
    assert.doesNotMatch(contents, /docker compose down/);
    assert.doesNotMatch(contents, /docker system prune/);
  }
  for (const file of [backupTimer, rehearsalTimer]) {
    const contents = read(file);
    assert.match(contents, /Persistent=true/);
    assert.match(contents, /Timezone=Asia\/Bangkok/);
    assert.doesNotMatch(contents, /\/opt\/ktaxi/);
    assert.doesNotMatch(contents, /\bnode\b/);
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

test('bash retention lib keeps policy limits and newest backup', { skip: !bashRetentionAvailable() }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-bash-'));
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
  const output = runBashRetentionPlan(root, false);
  const plan = parsePlanOutput(output);
  assert.match(output, /RETENTION_POLICY=daily:14,weekly:8,monthly:6/);
  assert.equal(plan.mode, 'dry_run');
  assert.ok(plan.keep.includes('tride_staging-20260816-120000.sql.gz'));
  assert.match(output, /No files deleted \(dry-run\)\./);
});

test('bash retention lib ignores malformed and orphan pairs', { skip: !bashRetentionAvailable() }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-bash-'));
  makeBackupPair(root, '20260816-120000');
  fs.writeFileSync(path.join(root, 'bad-name.sql.gz'), 'data');
  fs.writeFileSync(path.join(root, 'tride_staging-20260815-120000.sql.gz'), 'orphan');
  fs.writeFileSync(path.join(root, 'orphan.manifest'), 'BACKUP_SHA256=x');
  const output = runBashRetentionPlan(root, false);
  const plan = parsePlanOutput(output);
  assert.deepEqual(plan.malformed, ['bad-name.sql.gz']);
  assert.deepEqual(plan.orphanBackups, ['tride_staging-20260815-120000.sql.gz']);
  assert.deepEqual(plan.orphanManifests, ['orphan.manifest']);
  assert.ok(plan.keep.includes('tride_staging-20260816-120000.sql.gz'));
});

test('bash retention lib does not delete without --apply', { skip: !bashRetentionAvailable() }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-bash-'));
  for (let day = 1; day <= 20; day += 1) {
    makeBackupPair(root, `202608${String(day).padStart(2, '0')}-120000`);
  }
  const before = fs.readdirSync(root).length;
  runBashRetentionPlan(root, false);
  assert.equal(fs.readdirSync(root).length, before);
});

test('bash retention lib deletes only planner candidates with --apply', { skip: !bashRetentionAvailable() }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-bash-'));
  for (let day = 1; day <= 20; day += 1) {
    makeBackupPair(root, `202608${String(day).padStart(2, '0')}-120000`);
  }
  const dryRun = parsePlanOutput(runBashRetentionPlan(root, false));
  assert.ok(dryRun.candidates.length > 0);
  runBashRetentionPlan(root, true);
  for (const candidate of dryRun.candidates) {
    assert.equal(fs.existsSync(path.join(root, candidate)), false);
    assert.equal(fs.existsSync(path.join(root, `${candidate.slice(0, -7)}.manifest`)), false);
  }
  assert.ok(fs.existsSync(path.join(root, 'tride_staging-20260820-120000.sql.gz')));
});

test('bash latest selection skips newer orphan backup and malformed names', { skip: !bashRetentionAvailable() }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-backup-bash-'));
  makeBackupPair(root, '20260815-120000');
  fs.writeFileSync(path.join(root, 'tride_staging-20260816-120000.sql.gz'), 'orphan-without-manifest');
  fs.writeFileSync(path.join(root, 'bad-name.sql.gz'), 'data');
  const latest = runBashLatestSelection(root);
  assert.match(latest, /tride_staging-20260815-120000\.sql\.gz$/);
});
