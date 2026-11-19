function validInsuranceDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && Number(value.slice(0, 4)) >= 1900 && Number(value.slice(0, 4)) <= 2100
    && Number.isFinite(Date.parse(value + 'T00:00:00Z'))
    && new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) === value;
}

function driverInsurance(expiresOn, now = new Date()) {
  if (!validInsuranceDate(expiresOn)) return { expiresOn: null, status: 'MISSING' };
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  const part = name => parts.find(p => p.type === name).value;
  const today = `${part('year')}-${part('month')}-${part('day')}`;
  const expiry = new Date(expiresOn + 'T00:00:00Z');
  const lastDay = new Date(Date.UTC(expiry.getUTCFullYear(), expiry.getUTCMonth(), 0)).getUTCDate();
  const warning = new Date(Date.UTC(
    expiry.getUTCFullYear(), expiry.getUTCMonth() - 1,
    Math.min(expiry.getUTCDate(), lastDay),
  )).toISOString().slice(0, 10);
  return {
    expiresOn, status: today > expiresOn ? 'EXPIRED' : today >= warning ? 'EXPIRING' : 'VALID',
  };
}

module.exports = { driverInsurance, validInsuranceDate };
