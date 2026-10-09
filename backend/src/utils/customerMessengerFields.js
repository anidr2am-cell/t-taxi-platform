'use strict';

/** Transitional create-booking placeholders (contact connection M2); not real messenger data. */
const TRANSITIONAL_MESSENGER_TYPE = new Set(['PENDING']);
const TRANSITIONAL_MESSENGER_ID = new Set(['POST_CREATE', 'PENDING']);
const MESSENGER_TYPES = new Set(['KAKAO', 'LINE', 'WHATSAPP', 'SMS']);

const LEGACY_MESSENGER_TYPES = new Map([
  ['KAKAO', 'KAKAO'],
  ['KAKAO TALK', 'KAKAO'],
  ['KAKAOTALK', 'KAKAO'],
  ['LINE', 'LINE'],
  ['WHATSAPP', 'WHATSAPP'],
  ['SMS', 'SMS'],
  ['PHONE', 'SMS'],
  ['PHONE/SMS', 'SMS'],
]);

function normalizeMessengerType(value) {
  if (value == null) return null;
  const normalized = String(value).trim().toUpperCase().replace(/\s+/g, ' ');
  return LEGACY_MESSENGER_TYPES.get(normalized) ?? null;
}

function isTransitionalMessengerType(value) {
  if (value == null || value === '') return false;
  return TRANSITIONAL_MESSENGER_TYPE.has(String(value).trim());
}

function isTransitionalMessengerId(value) {
  if (value == null || value === '') return false;
  return TRANSITIONAL_MESSENGER_ID.has(String(value).trim());
}

function stripTransitionalMessengerPlaceholders(customer) {
  if (!customer || typeof customer !== 'object') {
    return customer;
  }
  const next = { ...customer };
  if (isTransitionalMessengerType(next.messengerType)) {
    delete next.messengerType;
  }
  if (isTransitionalMessengerId(next.messengerId)) {
    delete next.messengerId;
  }
  return next;
}

function pickPersistableMessengerMetadata(customer) {
  const out = {};
  if (customer?.messengerType && !isTransitionalMessengerType(customer.messengerType)) {
    out.messengerType = normalizeMessengerType(customer.messengerType) ?? customer.messengerType;
  }
  if (customer?.messengerId && !isTransitionalMessengerId(customer.messengerId)) {
    out.messengerId = customer.messengerId;
  }
  return out;
}

module.exports = {
  isTransitionalMessengerType,
  isTransitionalMessengerId,
  stripTransitionalMessengerPlaceholders,
  pickPersistableMessengerMetadata,
  normalizeMessengerType,
  MESSENGER_TYPES,
};
