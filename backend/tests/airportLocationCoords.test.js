const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

/** Keep in sync with frontend ThailandRegisteredAirports. */
const expected = {
  BKK: { lat: 13.6899990, lng: 100.7479240, name: 'Suvarnabhumi Airport' },
  DMK: { lat: 13.9132600, lng: 100.6020100, name: 'Don Mueang International Airport' },
  CNX: { lat: 18.7679959, lng: 98.9685630, name: 'Chiang Mai International Airport' },
  HKT: { lat: 8.1054010, lng: 98.3060540, name: 'Phuket International Airport' },
};

const bangkokCity = { lat: 13.7563, lng: 100.5018 };

function readSql(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', '..', relativePath), 'utf8');
}

function readDartCanonical() {
  return fs.readFileSync(
    path.join(
      __dirname,
      '..',
      '..',
      'frontend',
      'lib',
      'features',
      'booking',
      'models',
      'thailand_registered_airports.dart',
    ),
    'utf8',
  );
}

test('ops data-fix SQL covers four airports with non-city coordinates', () => {
  const sql = readSql('database/ops_airport_location_coords_fix.sql');

  assert.match(sql, /PROPOSED ops data-fix ONLY/i);
  assert.doesNotMatch(sql, /^\s*USE\s+\w+/m);
  assert.match(sql, /google_place_id = google_place_id/);
  assert.doesNotMatch(sql, /google_place_id\s*=\s*'ChIJ/);
  assert.match(sql, /START TRANSACTION/);
  assert.match(sql, /BOOKINGS: preview only/i);
  assert.doesNotMatch(sql, /^\s*UPDATE\s+bookings\b/im);

  for (const [code, values] of Object.entries(expected)) {
    assert.ok(sql.includes(`WHEN '${code}' THEN ${values.lat}`));
    assert.ok(sql.includes(`WHEN '${code}' THEN ${values.lng}`));
    assert.ok(sql.includes(values.name));
  }

  assert.ok(Math.abs(expected.BKK.lat - bangkokCity.lat) > 0.04);
  assert.ok(Math.abs(expected.BKK.lng - bangkokCity.lng) > 0.15);
});

test('pricing architecture seed updates airport coordinates for BKK/DMK/CNX/HKT', () => {
  const sql = readSql('database/15_pricing_architecture.sql');
  assert.match(sql, /type = 'AIRPORT'/);
  assert.ok(sql.includes("WHEN 'BKK' THEN 13.6899990"));
  assert.ok(sql.includes("WHEN 'DMK' THEN 13.9132600"));
  assert.ok(sql.includes("WHEN 'CNX' THEN 18.7679959"));
  assert.ok(sql.includes("WHEN 'HKT' THEN 8.1054010"));
});

test('BKK airport code stays distinct from BANGKOK city location code', () => {
  const sql = readSql('database/15_pricing_architecture.sql');
  assert.match(sql, /code = 'BANGKOK'/);
  assert.match(sql, /'BKK'/);
  assert.match(sql, /type = 'AIRPORT'/);
  assert.match(sql, /'CITY', 'Bangkok'/);
});

test('Flutter canonical airport file matches SQL coordinates', () => {
  const dart = readDartCanonical();
  for (const [code, values] of Object.entries(expected)) {
    assert.ok(dart.includes(`code: '${code}'`), `missing ${code}`);
    assert.ok(
      dart.includes(`latitude: ${String(values.lat).replace(/0+$/, '').replace(/\.$/, '')}`) ||
        dart.includes(`latitude: ${values.lat}`) ||
        dart.includes(`latitude: ${Number(values.lat)}`),
      `missing lat for ${code}`,
    );
  }
  assert.ok(dart.includes('latitude: 13.689999'));
  assert.ok(dart.includes('longitude: 100.747924'));
  assert.ok(dart.includes('latitude: 13.913260'));
  assert.ok(dart.includes('longitude: 100.602010'));
  assert.ok(dart.includes('latitude: 18.7679959'));
  assert.ok(dart.includes('longitude: 98.968563'));
  assert.ok(dart.includes('latitude: 8.105401'));
  assert.ok(dart.includes('longitude: 98.306054'));
  assert.ok(dart.includes('Samut Prakan 10540'));
});
