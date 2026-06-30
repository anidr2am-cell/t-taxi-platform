const fs = require('fs');
const path = require('path');

const databaseDir = path.resolve(__dirname, '..', '..', 'database');
const migrationPattern = /^\d+_.+\.sql$/;

function listMigrations() {
  return fs
    .readdirSync(databaseDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && migrationPattern.test(entry.name))
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
}

function findDuplicatePrefixes(files) {
  const byPrefix = new Map();
  for (const file of files) {
    const prefix = file.split('_')[0];
    const matches = byPrefix.get(prefix) || [];
    matches.push(file);
    byPrefix.set(prefix, matches);
  }
  return Array.from(byPrefix.entries()).filter(([, matches]) => matches.length > 1);
}

function main() {
  const files = listMigrations();
  if (files.length === 0) {
    console.error('No numbered SQL migration files found.');
    process.exit(1);
  }

  console.log('Migration execution order:');
  files.forEach((file, index) => {
    console.log(`${String(index + 1).padStart(2, '0')}. ${file}`);
  });

  const duplicatePrefixes = findDuplicatePrefixes(files);
  if (duplicatePrefixes.length > 0) {
    console.log('');
    console.log('Duplicate numeric prefixes detected:');
    duplicatePrefixes.forEach(([prefix, matches]) => {
      console.log(`- ${prefix}: ${matches.join(', ')}`);
    });
    console.log('This is allowed for existing migrations because execution order is lexicographic by full filename.');
  }
}

main();
