'use strict';

/** Transitional create-booking placeholders (contact connection M2); not real messenger data. */
const TRANSITIONAL_MESSENGER_TYPE = new Set(['PENDING']);
const TRANSITIONAL_MESSENGER_ID = new Set(['POST_CREATE', 'PENDING']);

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
    out.messengerType = customer.messengerType;
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
};
