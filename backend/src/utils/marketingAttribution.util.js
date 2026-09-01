const Joi = require('joi');

const UTM_PATTERN = /^[a-zA-Z0-9._-]{1,150}$/;
const PATH_PATTERN = /^\/[^\?#]{0,499}$/;
const HOST_PATTERN = /^[a-z0-9.-]{1,255}$/;
const EMAIL_PATTERN = /[^@]+@[^@]+\.[^@]+/;
const PHONE_PATTERN = /^\+?[0-9\s()-]{7,20}$/;

function looksLikePii(value) {
  if (typeof value !== 'string') return true;
  const trimmed = value.trim();
  if (!trimmed) return false;
  if (EMAIL_PATTERN.test(trimmed)) return true;
  if (PHONE_PATTERN.test(trimmed.replace(/\s/g, ''))) return true;
  if (trimmed.includes('@')) return true;
  return false;
}

function sanitizeUtmValue(value) {
  if (value == null) return null;
  const trimmed = String(value).trim();
  if (!trimmed || trimmed.length > 150) return null;
  if (looksLikePii(trimmed)) return null;
  if (!UTM_PATTERN.test(trimmed)) return null;
  return trimmed;
}

function sanitizeLandingPage(value) {
  if (value == null) return null;
  const trimmed = String(value).trim();
  if (!trimmed || !PATH_PATTERN.test(trimmed)) return null;
  return trimmed;
}

function sanitizeReferrerHost(value) {
  if (value == null) return null;
  const trimmed = String(value).trim().toLowerCase();
  if (!trimmed || !HOST_PATTERN.test(trimmed)) return null;
  if (looksLikePii(trimmed)) return null;
  return trimmed;
}

const marketingAttributionSchema = Joi.any().optional();

function normalizeMarketingTouch(touch) {
  if (!touch || typeof touch !== 'object') return null;
  const normalized = {
    source: sanitizeUtmValue(touch.source),
    medium: sanitizeUtmValue(touch.medium),
    campaign: sanitizeUtmValue(touch.campaign),
    content: sanitizeUtmValue(touch.content),
    term: sanitizeUtmValue(touch.term),
    landing_page: sanitizeLandingPage(touch.landingPage ?? touch.landing_page),
    referrer_host: sanitizeReferrerHost(touch.referrerHost ?? touch.referrer_host),
    captured_at: touch.capturedAt ?? touch.captured_at ?? null,
  };

  if (
    typeof normalized.captured_at !== 'string'
    || Number.isNaN(Date.parse(normalized.captured_at))
  ) {
    normalized.captured_at = new Date().toISOString();
  }

  const hasSignal = [
    normalized.source,
    normalized.medium,
    normalized.campaign,
    normalized.content,
    normalized.term,
    normalized.landing_page,
    normalized.referrer_host,
  ].some((value) => typeof value === 'string' && value.trim());

  if (!hasSignal) return null;
  return normalized;
}

function normalizeMarketingAttribution(input) {
  if (!input || typeof input !== 'object') return null;
  const firstTouch = normalizeMarketingTouch(input.firstTouch ?? input.first_touch);
  const lastTouch = normalizeMarketingTouch(input.lastTouch ?? input.last_touch);
  if (!firstTouch && !lastTouch) return null;
  return {
    ...(firstTouch ? { first_touch: firstTouch } : {}),
    ...(lastTouch ? { last_touch: lastTouch } : {}),
  };
}

module.exports = {
  marketingAttributionSchema,
  normalizeMarketingAttribution,
  sanitizeUtmValue,
  sanitizeLandingPage,
  sanitizeReferrerHost,
  looksLikePii,
};
