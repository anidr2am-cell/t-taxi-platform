const { isBookingReviewEligible } = require('./reviewEligibility.util');

const LOCALES = ['ko', 'en', 'zh', 'ja', 'th'];
const CHANNELS = ['KAKAO', 'LINE', 'WHATSAPP', 'SMS', 'EMAIL', 'OTHER'];
function parseMetadata(value) {
  if (typeof value === 'string') {
    try { return JSON.parse(value) || {}; } catch (_) { return {}; }
  }
  return value && typeof value === 'object' ? value : {};
}
function reviewRequestState(booking) {
  const metadata = parseMetadata(booking.metadata);
  const request = metadata.reviewRequest || {};
  return {
    eligible: isBookingReviewEligible(booking),
    introduced: Boolean(metadata.reviewRequestEligibleAt),
    locale: LOCALES.includes(metadata.locale) ? metadata.locale : null,
    status: request.sentAt ? 'SENT' : request.copiedAt ? 'COPIED' : 'NOT_REQUESTED',
    optedOut: request.optedOut === true,
    copiedAt: request.copiedAt || null,
    sentAt: request.sentAt || null,
    channel: request.channel || null,
    actorUserId: request.actorUserId || null,
    actorName: request.actorName || null,
  };
}
module.exports = { LOCALES, CHANNELS, parseMetadata, reviewRequestState };
