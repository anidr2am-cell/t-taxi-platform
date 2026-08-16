/**
 * Staging DB backup cycle helpers: retention, remote config, orchestration gates.
 * Pure logic for deterministic unit tests — host automation uses bash retention lib.
 * No Docker, rclone, or secret values.
 */
const fs = require('node:fs');
const path = require('node:path');

const APPROVED_BACKUP_ROOT = '/opt/t-ride/backups';
const BACKUP_LOCK_FILE = '/opt/t-ride/logs/backups/backup-cycle.lock';
const BACKUP_LOG_DIR = '/opt/t-ride/logs/backups';
const SOURCE_DB = 'tride_staging';
const BACKUP_FILENAME_RE = /^tride_staging-(\d{8})-(\d{6})\.sql\.gz$/;
const RETENTION_LIMITS = { daily: 14, weekly: 8, monthly: 6 };
const SECRET_ENV_KEYS = [
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'RCLONE_CONFIG_PASS',
  'DB_PASSWORD',
  'MYSQL_ROOT_PASSWORD',
];

function parseBoolean(value, defaultValue = false) {
  if (value == null || value === '') return defaultValue;
  const normalized = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return defaultValue;
}

function parseBackupConfig(env = {}) {
  return {
    remoteEnabled: parseBoolean(env.TRIDE_BACKUP_REMOTE_ENABLED, false),
    autoPrune: parseBoolean(env.TRIDE_BACKUP_AUTO_PRUNE, false),
    remoteName: String(env.TRIDE_BACKUP_REMOTE_NAME || '').trim(),
    remotePath: String(env.TRIDE_BACKUP_REMOTE_PATH || '').trim().replace(/\/+$/, ''),
    alertEnabled: parseBoolean(env.TRIDE_BACKUP_ALERT_ENABLED, false),
    alertScript: String(env.TRIDE_BACKUP_ALERT_SCRIPT || '').trim(),
  };
}

function assertRemoteConfigWhenEnabled(config) {
  if (!config.remoteEnabled) {
    return { ok: true, mode: 'disabled' };
  }
  const missing = [];
  if (!config.remoteName) missing.push('TRIDE_BACKUP_REMOTE_NAME');
  if (!config.remotePath) missing.push('TRIDE_BACKUP_REMOTE_PATH');
  if (missing.length > 0) {
    throw new Error(`Remote backup enabled but missing: ${missing.join(', ')}`);
  }
  return { ok: true, mode: 'enabled' };
}

function parseBackupFilename(filename) {
  const base = path.posix.basename(String(filename || ''));
  const match = base.match(BACKUP_FILENAME_RE);
  if (!match) {
    return { valid: false, filename: base, reason: 'malformed_filename' };
  }
  const datePart = match[1];
  const timePart = match[2];
  const year = Number(datePart.slice(0, 4));
  const month = Number(datePart.slice(4, 6));
  const day = Number(datePart.slice(6, 8));
  const hour = Number(timePart.slice(0, 2));
  const minute = Number(timePart.slice(2, 4));
  const second = Number(timePart.slice(4, 6));
  const timestampMs = Date.UTC(year, month - 1, day, hour, minute, second);
  return {
    valid: true,
    filename: base,
    backupPath: null,
    manifestPath: `${base.slice(0, -7)}.manifest`,
    datePart,
    timePart,
    timestampMs,
    dayKey: datePart,
    monthKey: datePart.slice(0, 6),
    weekKey: isoWeekKeyFromDateParts(year, month, day),
  };
}

function isoWeekKeyFromDateParts(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const isoYear = date.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const week = Math.ceil((((date - yearStart) / 86400000) + 1) / 7);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

function parseManifest(content) {
  const entries = {};
  for (const line of String(content || '').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index < 0) continue;
    entries[trimmed.slice(0, index).trim()] = trimmed.slice(index + 1).trim();
  }
  return entries;
}

function manifestMatchesBackup(manifest, backupFilename, backupSizeBytes, backupSha256) {
  if (!manifest) {
    return { ok: false, reason: 'missing_manifest' };
  }
  const expectedBase = path.basename(backupFilename);
  if (manifest.BACKUP_FILE && path.basename(manifest.BACKUP_FILE) !== expectedBase) {
    return { ok: false, reason: 'manifest_backup_file_mismatch' };
  }
  if (manifest.BACKUP_SHA256 && backupSha256 && manifest.BACKUP_SHA256 !== backupSha256) {
    return { ok: false, reason: 'manifest_sha256_mismatch' };
  }
  if (manifest.BACKUP_SIZE_BYTES && backupSizeBytes != null
    && String(manifest.BACKUP_SIZE_BYTES) !== String(backupSizeBytes)) {
    return { ok: false, reason: 'manifest_size_mismatch' };
  }
  return { ok: true };
}

function inventoryBackups(backupRoot, readFileSync = fs.readFileSync, statSync = fs.statSync, existsSync = fs.existsSync) {
  const root = backupRoot || APPROVED_BACKUP_ROOT;
  const malformed = [];
  const orphanBackups = [];
  const orphanManifests = [];
  const entries = [];

  let files = [];
  try {
    files = fs.readdirSync(root);
  } catch {
    return {
      entries: [],
      malformed,
      orphanBackups,
      orphanManifests,
    };
  }

  const backupNames = new Set();
  const manifestNames = new Set();

  for (const name of files) {
    if (name.endsWith('.sql.gz')) {
      const parsed = parseBackupFilename(name);
      if (!parsed.valid) {
        malformed.push(name);
        continue;
      }
      backupNames.add(name);
    } else if (name.endsWith('.manifest')) {
      manifestNames.add(name);
    }
  }

  for (const name of backupNames) {
    const parsed = parseBackupFilename(name);
    const backupPath = path.posix.join(root, name);
    const manifestPath = path.posix.join(root, parsed.manifestPath);
    if (!existsSync(manifestPath)) {
      orphanBackups.push(name);
      continue;
    }
    const manifest = parseManifest(readFileSync(manifestPath, 'utf8'));
    if (!manifest.BACKUP_SHA256) {
      orphanBackups.push(name);
      continue;
    }
    let backupSizeBytes = null;
    let backupSha256 = null;
    try {
      backupSizeBytes = statSync(backupPath).size;
    } catch {
      orphanBackups.push(name);
      continue;
    }
    backupSha256 = manifest.BACKUP_SHA256 || null;
    const match = manifestMatchesBackup(manifest, name, backupSizeBytes, backupSha256);
    if (!match.ok) {
      orphanBackups.push(name);
      continue;
    }
    entries.push({
      ...parsed,
      backupPath,
      manifestPath,
      hasManifest: true,
      manifestValid: true,
      backupSizeBytes,
      backupSha256,
    });
  }

  for (const manifestName of manifestNames) {
    const backupName = manifestName.replace(/\.manifest$/, '.sql.gz');
    if (!backupNames.has(backupName)) {
      orphanManifests.push(manifestName);
    }
  }

  entries.sort((a, b) => b.timestampMs - a.timestampMs);
  return { entries, malformed, orphanBackups, orphanManifests };
}

function classifyRetention(inventory, limits = RETENTION_LIMITS) {
  const { entries, malformed, orphanBackups, orphanManifests } = inventory;
  const keep = new Set();
  const tierAssignments = [];

  if (entries.length > 0) {
    keep.add(entries[0].filename);
    tierAssignments.push({ filename: entries[0].filename, tier: 'newest' });
  }

  let monthCount = 0;
  const monthSeen = new Set();
  for (const entry of entries) {
    if (monthCount >= limits.monthly) break;
    if (monthSeen.has(entry.monthKey)) continue;
    monthSeen.add(entry.monthKey);
    keep.add(entry.filename);
    tierAssignments.push({ filename: entry.filename, tier: 'monthly', monthKey: entry.monthKey });
    monthCount += 1;
  }

  let weekCount = 0;
  const weekSeen = new Set();
  for (const entry of entries) {
    if (weekCount >= limits.weekly) break;
    if (weekSeen.has(entry.weekKey)) continue;
    weekSeen.add(entry.weekKey);
    if (!keep.has(entry.filename)) {
      tierAssignments.push({ filename: entry.filename, tier: 'weekly', weekKey: entry.weekKey });
    }
    keep.add(entry.filename);
    weekCount += 1;
  }

  let dayCount = 0;
  const daySeen = new Set();
  for (const entry of entries) {
    if (dayCount >= limits.daily) break;
    if (daySeen.has(entry.dayKey)) continue;
    daySeen.add(entry.dayKey);
    if (!keep.has(entry.filename)) {
      tierAssignments.push({ filename: entry.filename, tier: 'daily', dayKey: entry.dayKey });
    }
    keep.add(entry.filename);
    dayCount += 1;
  }

  const deleteCandidates = entries
    .filter((entry) => !keep.has(entry.filename))
    .map((entry) => entry.filename);

  return {
    keep: [...keep],
    deleteCandidates,
    tierAssignments,
    malformed,
    orphanBackups,
    orphanManifests,
    limits,
  };
}

function buildRemoteObjectPrefix(backupFilename, remotePath) {
  const parsed = parseBackupFilename(backupFilename);
  if (!parsed.valid) {
    throw new Error(`Cannot build remote path for malformed backup filename: ${backupFilename}`);
  }
  const year = parsed.datePart.slice(0, 4);
  const month = parsed.datePart.slice(4, 6);
  const base = path.posix.basename(backupFilename);
  const manifestBase = `${base.slice(0, -7)}.manifest`;
  const prefix = `${remotePath.replace(/\/+$/, '')}/staging/db/${year}/${month}`;
  return {
    remoteDir: prefix,
    backupObject: `${prefix}/${base}`,
    manifestObject: `${prefix}/${manifestBase}`,
  };
}

function evaluatePruneGate(cycle) {
  const backupPass = cycle.BACKUP_RESULT === 'PASS';
  const remotePass = cycle.REMOTE_COPY_RESULT === 'PASS' && cycle.REMOTE_VERIFY_RESULT === 'PASS';
  const remoteSkipped = cycle.REMOTE_COPY_RESULT === 'SKIPPED_DISABLED';
  if (!backupPass) {
    return { allowed: false, reason: 'backup_not_pass' };
  }
  if (remoteSkipped) {
    return { allowed: false, reason: 'remote_disabled' };
  }
  if (!remotePass) {
    return { allowed: false, reason: 'remote_not_pass' };
  }
  if (!cycle.autoPrune) {
    return { allowed: false, reason: 'auto_prune_disabled' };
  }
  return { allowed: true, reason: 'all_gates_pass' };
}

function findLatestCompleteBackup(inventory) {
  return inventory.entries[0] || null;
}

function buildStructuredLogEntry(fields) {
  const safe = {};
  for (const [key, value] of Object.entries(fields || {})) {
    if (value == null) continue;
    const lowerKey = key.toLowerCase();
    if (SECRET_ENV_KEYS.some((secret) => lowerKey.includes(secret.toLowerCase()))) continue;
    if (/password|secret|token|key/i.test(lowerKey) && lowerKey !== 'idempotency_key') continue;
    safe[key] = value;
  }
  return safe;
}

function parseKeyValueOutput(content) {
  const entries = {};
  for (const line of String(content || '').split(/\r?\n/)) {
    const trimmed = line.trim();
    const index = trimmed.indexOf('=');
    if (index < 0) continue;
    entries[trimmed.slice(0, index).trim()] = trimmed.slice(index + 1).trim();
  }
  return entries;
}

function readKeyValueOrDefault(content, key, defaultValue = 'FAIL') {
  const value = parseKeyValueOutput(content)[key];
  if (value == null || value === '') return defaultValue;
  return value;
}

function invokesShellScriptViaBash(scriptContents, runnerVariable) {
  const pattern = new RegExp(`bash "\\$\\{${runnerVariable}\\}"`);
  return pattern.test(String(scriptContents || ''));
}

function envExampleContainsSecrets(content) {
  const lower = String(content || '').toLowerCase();
  return [
    'aws_secret',
    'access_key=',
    'secret_key=',
    'password=',
    'token=',
  ].some((needle) => lower.includes(needle) && !lower.includes('example') && !lower.includes('your_'));
}

module.exports = {
  APPROVED_BACKUP_ROOT,
  BACKUP_LOCK_FILE,
  BACKUP_LOG_DIR,
  SOURCE_DB,
  RETENTION_LIMITS,
  BACKUP_FILENAME_RE,
  parseBoolean,
  parseBackupConfig,
  assertRemoteConfigWhenEnabled,
  parseBackupFilename,
  isoWeekKeyFromDateParts,
  parseManifest,
  manifestMatchesBackup,
  inventoryBackups,
  classifyRetention,
  buildRemoteObjectPrefix,
  evaluatePruneGate,
  findLatestCompleteBackup,
  buildStructuredLogEntry,
  parseKeyValueOutput,
  readKeyValueOrDefault,
  invokesShellScriptViaBash,
  envExampleContainsSecrets,
};
