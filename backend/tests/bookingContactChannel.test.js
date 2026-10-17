'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { resolveBookingContactChannel } = require('../src/utils/bookingContactChannel');
const BookingContactConnectionService = require('../src/services/bookingContactConnection.service');
const settings = { defaultChannel: 'KAKAO', channels: [
  { code: 'LINE', enabled: true, addUrl: 'https://line.me/qa' },
  { code: 'KAKAO', enabled: true, addUrl: 'https://pf.kakao.com/qa' },
  { code: 'WHATSAPP', enabled: true, phoneNumber: '+66812345678' },
] };

test('preferred messenger overrides locale and configured default', () => {
  for (const type of ['LINE', 'KAKAO', 'WHATSAPP']) {
    assert.equal(resolveBookingContactChannel(type, settings), type);
  }
  assert.equal(resolveBookingContactChannel('kakao talk', settings), 'KAKAO');
  assert.equal(resolveBookingContactChannel('SMS', settings), 'KAKAO');
});

test('unconfigured or disabled preference falls back to usable default only', () => {
  const unavailable = { ...settings, channels: settings.channels.map(c =>
    c.code === 'LINE' ? { ...c, addUrl: '' } : c) };
  assert.equal(resolveBookingContactChannel('LINE', unavailable), 'KAKAO');
  assert.equal(resolveBookingContactChannel('LINE', { ...settings, channels: [
    { code: 'LINE', enabled: false, addUrl: 'https://line.me/qa' },
    { code: 'KAKAO', addUrl: 'http://invalid' },
    { code: 'WHATSAPP', phoneNumber: '' },
  ] }), null);
  assert.equal(resolveBookingContactChannel('SMS', { channels: settings.channels }), 'LINE');
});

test('managed new connections use preference even when an old client asks for Kakao; legacy rows keep selected channel', async () => {
  for (const managed of [true, false]) {
    let snapshot;
    const booking = { id: 1, booking_number: 'TX202610180099', contact_status: 'PENDING',
      metadata: JSON.stringify({ messengerType: 'LINE', ...(managed ? { contactChannelPolicy: 1 } : {}) }) };
    const conn = { beginTransaction: async () => {}, commit: async () => {}, rollback: async () => {}, release: () => {} };
    const service = new BookingContactConnectionService(
      { getConnection: async () => conn },
      { findByBookingNumberForUpdate: async () => booking, findById: async () => ({ ...booking, contact_channel: snapshot.contactChannel }) },
      { cancelActiveConnections: async () => {}, insertConnection: async () => 5,
        updateBookingContactSnapshot: async (_c, _id, row) => { snapshot = row; }, findById: async () => null },
      { assertCustomerOrGuestAccess: async () => {} },
      { getContactChannelsPublic: async () => settings },
    );
    const result = await service.startConnection(booking.booking_number, 'KAKAO', {}, null);
    assert.equal(result.contactChannel, managed ? 'LINE' : 'KAKAO');
    assert.equal(result.contactChannelManaged, managed);
    assert.equal(result.contactStatus, 'PENDING');
  }
});
