#!/usr/bin/env node
/**
 * CLI for staging backup retention planning and latest-backup selection.
 */
const fs = require('node:fs');
const path = require('node:path');
const {
  APPROVED_BACKUP_ROOT,
  inventoryBackups,
  classifyRetention,
  findLatestCompleteBackup,
} = require('./stagingDbBackupCycle');

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const selectLatest = args.includes('--select-latest');
const backupRoot = process.env.TRIDE_BACKUP_ROOT || APPROVED_BACKUP_ROOT;

const inventory = inventoryBackups(backupRoot);
const plan = classifyRetention(inventory);

if (selectLatest) {
  const latest = findLatestCompleteBackup(inventory);
  process.stdout.write(JSON.stringify({
    latest: latest
      ? {
        backupPath: latest.backupPath,
        manifestPath: latest.manifestPath,
        filename: latest.filename,
        timestampMs: latest.timestampMs,
      }
      : null,
  }));
  process.exit(latest ? 0 : 1);
}

console.log(`RETENTION_POLICY=daily:${plan.limits.daily},weekly:${plan.limits.weekly},monthly:${plan.limits.monthly}`);
console.log(`BACKUP_FILES_VALID=${inventory.entries.length}`);
console.log(`RETENTION_KEEP_COUNT=${plan.keep.length}`);
console.log(`RETENTION_DELETE_CANDIDATES=${plan.deleteCandidates.length}`);
console.log(`RETENTION_MODE=${apply ? 'apply' : 'dry_run'}`);

for (const name of plan.malformed) {
  console.log(`MALFORMED=${name}`);
}
for (const name of plan.orphanBackups) {
  console.log(`ORPHAN_BACKUP=${name}`);
}
for (const name of plan.orphanManifests) {
  console.log(`ORPHAN_MANIFEST=${name}`);
}
for (const assignment of plan.tierAssignments) {
  console.log(`KEEP_${assignment.tier.toUpperCase()}=${assignment.filename}`);
}
for (const name of plan.deleteCandidates) {
  console.log(`CANDIDATE=${name}`);
}

if (apply) {
  for (const name of plan.deleteCandidates) {
    const backupPath = path.join(backupRoot, name);
    const manifestPath = path.join(backupRoot, `${name.slice(0, -7)}.manifest`);
    fs.rmSync(backupPath, { force: true });
    fs.rmSync(manifestPath, { force: true });
    console.log(`DELETED=${backupPath}`);
  }
} else {
  console.log('No files deleted (dry-run).');
}
