const THAILAND_AIRPORT_NAME_TH = Object.freeze({
  BKK: 'ท่าอากาศยานสุวรรณภูมิ',
  DMK: 'ท่าอากาศยานดอนเมือง',
  CNX: 'ท่าอากาศยานเชียงใหม่',
  HKT: 'ท่าอากาศยานภูเก็ต',
  UTP: 'ท่าอากาศยานอู่ตะเภา',
});

function normalizeAirportIata(value) {
  const normalized = String(value ?? '').trim().toUpperCase();
  return /^[A-Z]{3}$/.test(normalized) ? normalized : null;
}

function getThailandAirportNameTh(iata) {
  const normalized = normalizeAirportIata(iata);
  if (!normalized) return null;
  return THAILAND_AIRPORT_NAME_TH[normalized] ?? null;
}

module.exports = {
  THAILAND_AIRPORT_NAME_TH,
  normalizeAirportIata,
  getThailandAirportNameTh,
};
