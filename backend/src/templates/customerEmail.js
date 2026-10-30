const copy = require('./customer-email.json');
const { receiptDocument } = require('./customerReceipt');
const { parseServiceDateTimeToMs } = require('../utils/serviceDateTime.util');
const { customerPaymentFromMetadata } = require('../utils/customerPayment');

const CUSTOMER_TYPES = Object.keys(copy.en.messages);
function normalizeLocale(value) {
  const lang = String(value || '').trim().toLowerCase().split(/[-_]/)[0];
  return Object.hasOwn(copy, lang) ? lang : null;
}
function metadata(value) {
  if (typeof value !== 'string') return value || {};
  try { return JSON.parse(value) || {}; } catch { return {}; }
}
function resolveEmailLocale(notification) {
  return normalizeLocale(metadata(notification.booking_metadata).locale)
    || normalizeLocale(notification.recipient_locale)
    || normalizeLocale(notification.payload?.locale)
    || 'en';
}
function isCustomerEmail(notification) {
  const customerAudience = notification.audience_role
    ? notification.audience_role === 'CUSTOMER'
    : notification.recipient_type === 'GUEST_BOOKING' || notification.recipient_user_role === 'CUSTOMER';
  return CUSTOMER_TYPES.includes(notification.type) && customerAudience;
}
function httpsUrl(value) {
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password ? url.href : ''; }
  catch { return ''; }
}
function bangkokDateTime(value) {
  const ms = parseServiceDateTimeToMs(value);
  if (ms == null) return null;
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok', calendar: 'gregory', year: 'numeric', month: '2-digit',
    day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(ms));
  const get = (type) => parts.find((p) => p.type === type).value;
  return `${get('year')}-${get('month')}-${get('day')} ${get('hour')}:${get('minute')}`;
}
function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function renderCustomerEmail(notification, { origin = 'https://trider.taxi', googleReviewUrl = '' } = {}) {
  const locale = resolveEmailLocale(notification);
  const t = copy[locale];
  const template = t.messages[notification.type];
  if (!template) return null;
  let base;
  try { base = new URL(origin).origin; } catch { base = 'https://trider.taxi'; }
  const number = String(notification.booking_number || notification.payload?.bookingNumber || '');
  const bookingUrl = new URL('/booking/lookup', base);
  bookingUrl.searchParams.set('bookingNumber', number);
  bookingUrl.searchParams.set('lang', locale);
  const supportUrl = new URL('/support', base);
  supportUrl.searchParams.set('lang', locale);
  const googleUrl = httpsUrl(googleReviewUrl);
  const review = ['TRIP_ENDED', 'REVIEW_REQUESTED'].includes(notification.type);
  const body = review ? t.review
    .replace('{googleLine}', googleUrl ? `${t.google.replace('{googleUrl}', googleUrl)}\n` : '')
    .replace('{bookingUrl}', bookingUrl.href) : template.body;
  const pickup = bangkokDateTime(notification.scheduled_pickup_at);
  const route = [notification.origin_address, notification.destination_address].filter(Boolean).join(' → ');
  const rawAmount = notification.booking_total_amount;
  const amount = rawAmount == null || rawAmount === '' ? null : Number(rawAmount);
  const receipt = notification.type === 'BOOKING_CREATED';
  const vehicle = t.vehicles?.[notification.booking_vehicle_type];
  const payment = customerPaymentFromMetadata(notification.booking_metadata, notification.booking_payment_method);
  const paymentLabel = t.paymentMethods?.[payment.method];
  let lines = [body, '', `${t.booking}: ${number}`,
    pickup ? `${t.pickup}: ${pickup}` : null,
    route ? `${t.route}: ${route}` : null,
    receipt && vehicle ? `${t.vehicle}: ${vehicle}` : null,
    amount != null && Number.isFinite(amount) && amount >= 0
      ? `${t.amount}: ${new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(amount)} ${t.currency}` : null,
    receipt && paymentLabel ? `${t.paymentMethod}: ${paymentLabel}` : null,
    '', t.fare, t.cancel, t.payment, '', `${t.lookup}: ${bookingUrl.href}`, `${t.support}: ${supportUrl.href}`,
  ].filter((line) => line != null);
  const document = notification.type === 'TRIP_ENDED'
    ? receiptDocument(notification, {locale, labels:t, pickupAt:pickup, issuedAt:bangkokDateTime(notification.created_at), escapeHtml}) : null;
  if(document) lines=[...document.lines,'',body,'',t.fare,t.cancel,t.payment,'',`${t.lookup}: ${bookingUrl.href}`,`${t.support}: ${supportUrl.href}`];
  // Allowlist only the itinerary above; never interpolate arbitrary payload/body or contact fields.
  const text = lines.join('\n');
  const htmlLines = text.split('\n').map((line) => {
    const safe = escapeHtml(line);
    return `<p>${safe.replace(/https?:\/\/[^\s<]+/g, (url) => `<a href="${url}">${url}</a>`) || '<br>'}</p>`;
  }).join('\n');
  const subject=document?.subject || template.subject;
  const documentHtml=document ? document.html+lines.slice(document.lines.length).map(line=>'<p>'+escapeHtml(line).replace(/https?:\/\/[^\s<]+/g,(url)=>`<a href="${url}">${url}</a>` )+'</p>').join('\n') : htmlLines;
  return { subject, text,
    html: `<!doctype html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(subject)}</title></head><body${document ? ' style="margin:0;background:#f3f7f6;font-family:Arial,sans-serif;color:#243936"' : ''}><main${document ? ' style="max-width:640px;margin:24px auto;background:white;padding:20px;overflow-wrap:anywhere"' : ''}>${document ? '' : `<h1>${escapeHtml(subject)}</h1>`}${documentHtml}</main></body></html>` };
}
module.exports = { copy, CUSTOMER_TYPES, normalizeLocale, resolveEmailLocale, isCustomerEmail, bangkokDateTime, renderCustomerEmail };
