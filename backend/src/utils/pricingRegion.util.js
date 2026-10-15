const { haversineKm } = require('./geo.util');

function contains(region, lat, lng) {
  if (lat == null || lng == null || !Number.isFinite(Number(lat)) || !Number.isFinite(Number(lng))) return false;
  const g = typeof region.geometry === 'string' ? JSON.parse(region.geometry) : region.geometry;
  if (g.type === 'Circle') return haversineKm(lat, lng, g.lat, g.lng) <= g.radiusKm;
  const ring = g.coordinates[0];
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [x, y] = ring[i]; const [xx, yy] = ring[j];
    const cross = (lng - x) * (yy - y) - (lat - y) * (xx - x);
    if (Math.abs(cross) < 1e-10 && lng >= Math.min(x, xx) && lng <= Math.max(x, xx)
      && lat >= Math.min(y, yy) && lat <= Math.max(y, yy)) return true;
    if ((y > lat) !== (yy > lat) && lng < (xx - x) * (lat - y) / (yy - y) + x) inside = !inside;
  }
  return inside;
}

function matchRegion(regions, lat, lng, airportIata) {
  const active = regions.filter(r => r.is_active === 1 || r.is_active === true);
  if (airportIata) return active.find(r => r.airport_iata === String(airportIata).toUpperCase()) || null;
  return active.filter(r => contains(r, lat, lng))
    .sort((a, b) => b.priority - a.priority || a.code.localeCompare(b.code))[0] || null;
}
module.exports = { contains, matchRegion };
