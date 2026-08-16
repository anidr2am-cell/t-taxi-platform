/**
 * Pure helpers for staging DB backup / restore rehearsal runners.
 * No secrets, no Docker calls — safe for unit tests on any host.
 */
const path = require('node:path');

const APPROVED_BACKUP_ROOT = '/opt/t-ride/backups';
const APPROVED_SOURCE_DB = 'tride_staging';
const APPROVED_SOURCE_CONTAINER = 'tride-db';
const REHEARSAL_CONTAINER = 'tride-restore-rehearsal';
const REHEARSAL_DB = 'tride_restore_rehearsal';
const FORBIDDEN_PATH_PREFIXES = ['/opt/ktaxi'];
const SECRET_MANIFEST_KEYS = [
  'password',
  'token',
  'secret',
  'connection_string',
  'mysql_password',
  'root_password',
];
const PII_MANIFEST_KEYS = [
  'customer_email',
  'customer_phone',
  'guest_access_token',
];

function normalizeAbsolutePath(filePath) {
  return path.resolve(String(filePath || '').trim());
}

function assertApprovedBackupPath(backupPath, backupRoot = APPROVED_BACKUP_ROOT) {
  const resolvedBackup = normalizeAbsolutePath(backupPath);
  const resolvedRoot = normalizeAbsolutePath(backupRoot);
  if (!resolvedBackup.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw new Error(`Backup path must be under ${resolvedRoot}`);
  }
  if (!resolvedBackup.endsWith('.sql.gz')) {
    throw new Error('Backup path must end with .sql.gz');
  }
  for (const prefix of FORBIDDEN_PATH_PREFIXES) {
    if (resolvedBackup.startsWith(prefix)) {
      throw new Error(`Backup path must not be under ${prefix}`);
    }
  }
  return resolvedBackup;
}

function assertApprovedSourceDb(dbName) {
  if (dbName !== APPROVED_SOURCE_DB) {
    throw new Error(`Refusing backup source DB ${dbName}; expected ${APPROVED_SOURCE_DB}`);
  }
}

function assertApprovedSourceContainer(containerName) {
  if (containerName !== APPROVED_SOURCE_CONTAINER) {
    throw new Error(`Refusing backup source container ${containerName}; expected ${APPROVED_SOURCE_CONTAINER}`);
  }
}

function assertRehearsalContainerName(containerName) {
  if (containerName !== REHEARSAL_CONTAINER) {
    throw new Error(`Unexpected rehearsal container ${containerName}; expected ${REHEARSAL_CONTAINER}`);
  }
}

function assertRehearsalDbName(dbName) {
  if (dbName !== REHEARSAL_DB) {
    throw new Error(`Unexpected rehearsal DB ${dbName}; expected ${REHEARSAL_DB}`);
  }
}

function buildAtomicBackupPaths(backupRoot, timestamp, dbName = APPROVED_SOURCE_DB) {
  const finalPath = path.posix.join(backupRoot, `${dbName}-${timestamp}.sql.gz`);
  return {
    finalPath,
    partialPath: `${finalPath}.partial`,
    manifestPath: `${finalPath.slice(0, -7)}.manifest`,
  };
}

function parseManifest(content) {
  const entries = {};
  for (const line of String(content || '').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index < 0) continue;
    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim();
    entries[key] = value;
  }
  return entries;
}

function manifestContainsForbiddenSecrets(content) {
  const lower = String(content || '').toLowerCase();
  return SECRET_MANIFEST_KEYS.some((key) => lower.includes(`${key}=`));
}

function manifestContainsPiiKeys(content) {
  const lower = String(content || '').toLowerCase();
  return PII_MANIFEST_KEYS.some((key) => lower.includes(`${key}=`));
}

function compareManifestCounts(sourceManifest, restoredManifest, keys) {
  const mismatches = [];
  for (const key of keys) {
    if (sourceManifest[key] !== restoredManifest[key]) {
      mismatches.push({ key, expected: sourceManifest[key], actual: restoredManifest[key] });
    }
  }
  return mismatches;
}

module.exports = {
  APPROVED_BACKUP_ROOT,
  APPROVED_SOURCE_DB,
  APPROVED_SOURCE_CONTAINER,
  REHEARSAL_CONTAINER,
  REHEARSAL_DB,
  assertApprovedBackupPath,
  assertApprovedSourceDb,
  assertApprovedSourceContainer,
  assertRehearsalContainerName,
  assertRehearsalDbName,
  buildAtomicBackupPaths,
  parseManifest,
  manifestContainsForbiddenSecrets,
  manifestContainsPiiKeys,
  compareManifestCounts,
};
