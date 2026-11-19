const { contains } = require('./pricingRegion.util');
const { normalizeAirportIata } = require('../constants/thailandAirports.constants');

function pointForBooking(row) {
  const side = row.service_type_code === 'AIRPORT_PICKUP' ? 'origin'
    : row.service_type_code === 'AIRPORT_DROPOFF' ? 'destination' : null;
  if (!side) return null;
  const lat = row[`${side}_lat`], lng = row[`${side}_lng`];
  if (lat == null || lng == null || String(lat).trim() === '' || String(lng).trim() === '') return null;
  if (!Number.isFinite(Number(lat)) || !Number.isFinite(Number(lng)) || Math.abs(Number(lat)) > 90 || Math.abs(Number(lng)) > 180) return null;
  return { lat: Number(lat), lng: Number(lng) };
}
function explicitAirport(row) {
  return [row.airport_iata, row.airport_code_custom].find(v => v != null && String(v).trim() !== '');
}
function airportFromRegions(row, regions = []) {
  const explicit = explicitAirport(row);
  // Existing explicit codes remain authoritative, including other airports.
  if (explicit !== undefined) return normalizeAirportIata(explicit);
  const point = pointForBooking(row);
  if (!point) return null;
  const matches = new Set(regions.filter(region => {
    if (!(region.is_active === 1 || region.is_active === true) || !normalizeAirportIata(region.airport_iata)) return false;
    try { return contains(region, point.lat, point.lng); } catch (_) { return false; }
  }).map(region => normalizeAirportIata(region.airport_iata)));
  // Never guess from address text, city proximity or an ambiguous overlap.
  return matches.size === 1 ? [...matches][0] : null;
}
async function resolveBookingAirport(row, repository, conn) {
  if (explicitAirport(row) !== undefined || !pointForBooking(row)) return airportFromRegions(row);
  return airportFromRegions(row, await repository.findActiveAirportRegions(conn));
}
module.exports = { pointForBooking, explicitAirport, airportFromRegions, resolveBookingAirport };
