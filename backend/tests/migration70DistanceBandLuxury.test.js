const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
  path.resolve(__dirname, '../../database/70_distance_band_and_luxury_deactivation.sql'),
  'utf8',
);
const rollback = fs.readFileSync(
  path.resolve(__dirname, '../../database/rollback/70_distance_band_and_luxury_deactivation.rollback.sql'),
  'utf8',
);

test('migration 70 makes every two-decimal distance-band boundary continuous without overlap', () => {
  assert.match(migration, /SET max_km = 11\.99[\s\S]*min_km = 0\.00[\s\S]*max_km = 12\.00/);
  assert.match(migration, /SET min_km = 12\.00,[\s\S]*max_km = 50\.99[\s\S]*min_km = 13\.00[\s\S]*max_km = 50\.00/);
  assert.match(migration, /SET max_km = 100\.99[\s\S]*min_km = 51\.00[\s\S]*max_km = 100\.00/);
  assert.match(migration, /SET max_km = 145\.99[\s\S]*min_km = 101\.00[\s\S]*max_km = 145\.00/);
  assert.match(rollback, /SET max_km = 12\.00[\s\S]*max_km = 11\.99/);
  assert.match(rollback, /SET min_km = 13\.00,[\s\S]*max_km = 50\.00[\s\S]*min_km = 12\.00[\s\S]*max_km = 50\.99/);
  assert.match(rollback, /SET max_km = 100\.00[\s\S]*max_km = 100\.99/);
  assert.match(rollback, /SET max_km = 145\.00[\s\S]*max_km = 145\.99/);
});

test('migration 70 only toggles active flags for LUXURY and capacity rule 6', () => {
  assert.match(migration, /UPDATE vehicle_capacity_rules vcr[\s\S]*vcr\.id = 6[\s\S]*vt\.code = 'LUXURY'/);
  assert.match(migration, /UPDATE vehicle_types[\s\S]*SET is_active = 0[\s\S]*code = 'LUXURY'/);
  assert.doesNotMatch(migration, /DELETE\s+FROM/i);
  assert.match(rollback, /UPDATE vehicle_types[\s\S]*SET is_active = 1[\s\S]*code = 'LUXURY'/);
  assert.match(rollback, /UPDATE vehicle_capacity_rules vcr[\s\S]*SET vcr\.is_active = 1[\s\S]*vcr\.id = 6/);
  assert.doesNotMatch(rollback, /DELETE\s+FROM/i);
});
