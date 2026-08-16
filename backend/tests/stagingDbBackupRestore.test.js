process.env.NODE_ENV = 'test';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const helpers = require('../scripts/stagingDbBackupRestore');

const scriptsDir = path.resolve(__dirname, '../scripts');
const backupRunner = path.join(scriptsDir, 'run-staging-db-backup.sh');
const restoreRunner = path.join(scriptsDir, 'run-staging-db-restore-rehearsal.sh');
const pruneRunner = path.join(scriptsDir, 'prune-staging-db-backups.sh');
const guards = path.join(scriptsDir, 'staging-db-backup-guards.sh');
const manifestSql = path.join(scriptsDir, 'staging-db-backup-manifest.sql');
const verifySql = path.join(scriptsDir, 'staging-db-restore-rehearsal-verify.sql');

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

test('backup runner refuses non-tride_staging DB name', () => {
  const guardContents = read(guards);
  const backupContents = read(backupRunner);
  assert.match(guardContents, /SOURCE_DB="tride_staging"/);
  assert.match(guardContents, /Refusing backup source DB/);
  assert.match(backupContents, /assert_source_db_name/);
});

test('backup runner refuses unexpected DB container', () => {
  const guardContents = read(guards);
  const backupContents = read(backupRunner);
  assert.match(guardContents, /SOURCE_CONTAINER="tride-db"/);
  assert.match(backupContents, /assert_source_container_name/);
});

test('backup runner uses atomic partial file before final rename', () => {
  const contents = read(backupRunner);
  assert.match(contents, /\.partial/);
  assert.match(contents, /mv "\$\{PARTIAL_FILE\}" "\$\{FINAL_FILE\}"/);
  assert.match(contents, /rm -f "\$\{PARTIAL_FILE\}"/);
});

test('backup runner performs gzip integrity and sha256 recording', () => {
  const contents = read(backupRunner);
  assert.match(contents, /gzip -t/);
  assert.match(contents, /sha256sum/);
  assert.match(contents, /BACKUP_SHA256=/);
  assert.match(contents, /GZIP_TEST=PASS/);
});

test('backup runner uses mariadb-dump with MariaDB-safe online options', () => {
  const contents = read(backupRunner);
  assert.match(contents, /mariadb-dump --single-transaction --quick --routines --triggers --events/);
  assert.doesNotMatch(contents, /mysqldump/);
});

test('restore runner refuses backup outside approved path', () => {
  assert.throws(
    () => helpers.assertApprovedBackupPath('/tmp/evil/tride_staging-20260816.sql.gz'),
    /must be under/,
  );
  assert.throws(
    () => helpers.assertApprovedBackupPath('/opt/ktaxi/backups/tride_staging-20260816.sql.gz'),
    /must be under/,
  );
  const approved = helpers.assertApprovedBackupPath(
    '/opt/t-ride/backups/tride_staging-20260816-120000.sql.gz',
  );
  assert.match(approved, /tride_staging-20260816-120000\.sql\.gz$/);
});

test('restore runner uses disposable rehearsal container with tmpfs storage', () => {
  const guardContents = read(guards);
  const contents = read(restoreRunner);
  assert.match(guardContents, /REHEARSAL_CONTAINER="tride-restore-rehearsal"/);
  assert.match(guardContents, /MARIADB_IMAGE="mariadb:10\.11"/);
  assert.match(contents, /"\$\{MARIADB_IMAGE\}"/);
  assert.doesNotMatch(contents, /tride_mysql_data/);
  assert.doesNotMatch(contents, /echo.*PASSWORD/i);
});

test('restore runner does not publish public port or use tride-db container', () => {
  const contents = read(restoreRunner);
  assert.doesNotMatch(contents, /(--publish|-p)[0-9]+:[0-9]+/);
  assert.doesNotMatch(contents, /docker exec tride-db/);
  assert.doesNotMatch(contents, /docker inspect tride-db/);
  assert.match(contents, /RESTORE_USES_TRIDE_DB=NO/);
  assert.match(contents, /PUBLIC_PORT_PUBLISHED=NO/);
});

test('restore runner installs EXIT trap for targeted container cleanup only', () => {
  const contents = read(restoreRunner);
  assert.match(contents, /trap cleanup EXIT/);
  assert.match(contents, /docker rm -f "\$\{REHEARSAL_CONTAINER\}"/);
  assert.match(contents, /local rc=\$\?/);
  assert.match(contents, /exit "\$\{rc\}"/);
});

test('runners forbid docker prune and DROP DATABASE tride_staging', () => {
  for (const file of [backupRunner, restoreRunner, pruneRunner]) {
    const contents = read(file);
    assert.doesNotMatch(contents, /docker system prune/);
    assert.doesNotMatch(contents, /docker volume prune/);
    assert.doesNotMatch(contents, /docker container prune/);
    assert.doesNotMatch(contents, /docker compose down/);
    assert.doesNotMatch(contents, /DROP DATABASE[^;\n]*tride_staging/i);
    assert.doesNotMatch(contents, /cd \/opt\/ktaxi/);
    assert.doesNotMatch(contents, /source \/opt\/ktaxi/);
  }
  const guardContents = read(guards);
  assert.match(guardContents, /assert_no_prune_commands/);
  assert.match(guardContents, /assert_no_staging_drop/);
});

test('manifest and verification SQL are SELECT/read-only', () => {
  for (const file of [manifestSql, verifySql]) {
    const sql = read(file);
    assert.doesNotMatch(sql, /\bINSERT\b/i);
    assert.doesNotMatch(sql, /\bUPDATE\b/i);
    assert.doesNotMatch(sql, /\bDELETE\b/i);
    assert.doesNotMatch(sql, /\bDROP\b/i);
    assert.doesNotMatch(sql, /\bALTER\b/i);
    assert.doesNotMatch(sql, /\bCREATE\b/i);
    assert.match(sql, /ROW_COUNT_bookings=/);
    assert.match(sql, /CONSTRAINT_uk_notifications_idempotency=/);
  }
});

test('manifest parser rejects secret-like keys and sample manifest stays safe', () => {
  const sample = [
    'BACKUP_TIMESTAMP=20260816-120000',
    'DB_NAME=tride_staging',
    'TABLE_COUNT=84',
    'ROW_COUNT_bookings=120',
    'CONSTRAINT_uk_notifications_idempotency=1',
    'LATEST_BOOKING_NUMBER=TX202608160001',
  ].join('\n');
  assert.equal(helpers.manifestContainsForbiddenSecrets(sample), false);
  assert.equal(helpers.manifestContainsPiiKeys(sample), false);
  const parsed = helpers.parseManifest(sample);
  assert.equal(parsed.DB_NAME, 'tride_staging');
  assert.equal(parsed.TABLE_COUNT, '84');
});

test('atomic backup path helper uses timestamped final and partial paths', () => {
  const paths = helpers.buildAtomicBackupPaths('/opt/t-ride/backups', '20260816-120000');
  assert.equal(paths.finalPath, '/opt/t-ride/backups/tride_staging-20260816-120000.sql.gz');
  assert.equal(paths.partialPath, '/opt/t-ride/backups/tride_staging-20260816-120000.sql.gz.partial');
  assert.equal(paths.manifestPath, '/opt/t-ride/backups/tride_staging-20260816-120000.manifest');
});

test('restore rehearsal compares restored counts against manifest keys', () => {
  const source = helpers.parseManifest('TABLE_COUNT=10\nROW_COUNT_bookings=3');
  const restored = helpers.parseManifest('TABLE_COUNT=10\nROW_COUNT_bookings=3');
  assert.deepEqual(helpers.compareManifestCounts(source, restored, ['TABLE_COUNT', 'ROW_COUNT_bookings']), []);
  const mismatches = helpers.compareManifestCounts(
    source,
    helpers.parseManifest('TABLE_COUNT=9\nROW_COUNT_bookings=3'),
    ['TABLE_COUNT'],
  );
  assert.equal(mismatches.length, 1);
  assert.equal(mismatches[0].key, 'TABLE_COUNT');
});

test('prune helper defaults to dry-run and does not install cron', () => {
  const contents = read(pruneRunner);
  assert.match(contents, /staging-db-backup-retention-plan\.js/);
  assert.match(contents, /--apply/);
  assert.doesNotMatch(contents, /crontab/);
  assert.doesNotMatch(contents, /systemctl enable/);
});

test('backup runner does not print database password', () => {
  const contents = read(backupRunner);
  assert.doesNotMatch(contents, /echo.*DB_PASSWORD/i);
  assert.doesNotMatch(contents, /echo.*MYSQL_ROOT_PASSWORD/i);
  assert.doesNotMatch(contents, /printf.*PASSWORD/i);
});

test('restore runner restores into tride_restore_rehearsal not live staging DB', () => {
  const guardContents = read(guards);
  const contents = read(restoreRunner);
  assert.match(guardContents, /REHEARSAL_DB="tride_restore_rehearsal"/);
  assert.match(contents, /CREATE DATABASE/);
  assert.match(contents, /\$\{REHEARSAL_DB\}/);
  assert.doesNotMatch(contents, /docker exec tride-db/);
});

test('cleanup still runs on restore failure via EXIT trap', () => {
  const contents = read(restoreRunner);
  const trapIndex = contents.indexOf('trap cleanup EXIT');
  const failIndex = contents.indexOf('RESTORE_REHEARSAL=FAIL');
  assert.ok(trapIndex >= 0);
  assert.ok(failIndex > trapIndex);
});

test('CREATE DATABASE command uses exact rehearsal DB name without shell backticks', () => {
  const sql = helpers.buildCreateRehearsalDatabaseSql();
  const command = helpers.buildCreateRehearsalDatabaseMysqlCommand();
  assert.equal(
    sql,
    'CREATE DATABASE tride_restore_rehearsal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
  );
  assert.match(command, /CREATE DATABASE tride_restore_rehearsal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;/);
  assert.doesNotMatch(sql, /CREATE DATABASE  CHARACTER/);
  assert.equal(helpers.sqlUsesShellBacktickSubstitution(sql), false);
  assert.equal(helpers.sqlUsesShellBacktickSubstitution(command), false);
});

test('restore runner CREATE DATABASE avoids nested backtick command substitution', () => {
  const contents = read(restoreRunner);
  assert.match(contents, /-e 'CREATE DATABASE \$\{REHEARSAL_DB\} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'/);
  assert.match(contents, /CREATE DATABASE failed/);
  assert.doesNotMatch(contents, /CREATE DATABASE `\$\{REHEARSAL_DB\}`/);
  assert.doesNotMatch(contents, /CREATE DATABASE `'\$\{REHEARSAL_DB\}'`/);
  assert.doesNotMatch(contents, /CREATE DATABASE  CHARACTER/);
  assert.doesNotMatch(contents, /\beval\b/);
});

test('CREATE DATABASE failure exits non-zero and cleanup removes rehearsal container and VERIFY_TMP', () => {
  const contents = read(restoreRunner);
  assert.match(contents, /CREATE DATABASE failed/);
  assert.match(contents, /if ! docker exec "\$\{REHEARSAL_CONTAINER\}" sh -lc/);
  assert.match(contents, /VERIFY_TMP="\$\(mktemp\)"/);
  assert.match(contents, /rm -f "\$\{VERIFY_TMP\}"/);
  const cleanupBlock = contents.slice(contents.indexOf('cleanup()'), contents.indexOf('trap cleanup EXIT') + 20);
  assert.match(cleanupBlock, /local rc=\$\?/);
  assert.match(cleanupBlock, /exit "\$\{rc\}"/);
  assert.match(cleanupBlock, /docker rm -f "\$\{REHEARSAL_CONTAINER\}"/);

  const simulated = helpers.simulateRestoreCleanup(1, {
    verifyTmp: '/tmp/restore-verify-abc',
    removeContainer: true,
  });
  assert.equal(simulated.exitCode, 1);
  assert.deepEqual(simulated.actions, [
    { type: 'remove_verify_tmp', path: '/tmp/restore-verify-abc' },
    { type: 'remove_container', name: 'tride-restore-rehearsal' },
  ]);
});

test('backup dump includes CREATE DATABASE so restore rewrite is required', () => {
  const backupContents = read(backupRunner);
  assert.equal(helpers.backupDumpRequiresDatabaseRewrite(backupContents), true);
  assert.match(read(restoreRunner), /sed "s\/\\`\$\{SOURCE_DB\}\\`\/\\`\$\{REHEARSAL_DB\}\\`\/g"/);
});

test('restore target remains tride_restore_rehearsal and never tride_staging', () => {
  const guardContents = read(guards);
  const restoreContents = read(restoreRunner);
  assert.match(guardContents, /SOURCE_DB="tride_staging"/);
  assert.match(guardContents, /REHEARSAL_DB="tride_restore_rehearsal"/);
  assert.doesNotMatch(restoreContents, /mysql.*tride_staging/);
  assert.throws(() => helpers.assertRehearsalDbName('tride_staging'), /Unexpected rehearsal DB/);
});

test('restore runner does not print secrets or use eval', () => {
  const contents = read(restoreRunner);
  assert.doesNotMatch(contents, /\beval\b/);
  assert.doesNotMatch(contents, /echo.*PASSWORD/i);
  assert.doesNotMatch(contents, /printf.*PASSWORD/i);
});
