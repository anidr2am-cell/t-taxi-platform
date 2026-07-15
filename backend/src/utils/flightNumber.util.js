const FLIGHT_NUMBER_INVALID_MESSAGE =
  'Invalid flight number format. Examples: TG401, 7C2203';

function normalizeFlightNumber(value) {
  if (value == null) return null;
  const trimmed = String(value).trim();
  if (!trimmed) return null;
  return trimmed
    .replace(/\s+/gu, '')
    .toUpperCase()
    .replace(/^([A-Z0-9]{2}|[A-Z]{3})-(?=\d)/u, '$1');
}

function parseFlightNumber(value) {
  const normalized = normalizeFlightNumber(value);
  if (!normalized) return null;

  const icao = normalized.match(/^([A-Z]{3})(\d{1,4})([A-Z]?)$/u);
  if (icao) {
    if (icao[2].startsWith('0')) return null;
    return { flightNumber: normalized, airlineCode: icao[1] };
  }

  const iata = normalized.match(/^([A-Z0-9]{2})(\d{1,4})([A-Z]?)$/u);
  if (!iata) return null;
  if (!/[A-Z]/u.test(iata[1])) return null;
  if (iata[2].startsWith('0')) return null;

  return { flightNumber: normalized, airlineCode: iata[1] };
}

function isValidFlightNumber(value) {
  return parseFlightNumber(value) !== null;
}

function extractAirlineCode(value) {
  return parseFlightNumber(value)?.airlineCode ?? null;
}

module.exports = {
  FLIGHT_NUMBER_INVALID_MESSAGE,
  extractAirlineCode,
  isValidFlightNumber,
  normalizeFlightNumber,
  parseFlightNumber,
};
