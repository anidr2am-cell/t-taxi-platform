const ERROR_CODES = require('../../constants/errorCodes');
const container = require('../../helpers/container');
const { guestBookingRoom } = require('../realtime');

function registerBookingHandlers(_io, socket) {
  socket.on('booking:urgent-negotiation:subscribe', async (payload = {}, ack) => {
    try {
      const bookingNumber = String(payload.bookingNumber ?? '').trim();
      if (!bookingNumber) {
        throw new Error('bookingNumber required');
      }

      const authUser = socket.data.authUser ?? null;
      const guestAccessToken = socket.data.guestAccessToken ?? null;
      const status = await container.get('urgentNegotiationService')
        .getCustomerNegotiationStatus(bookingNumber, {
          authUser,
          guestAccessToken,
        });

      const room = guestBookingRoom(status.bookingId);
      await socket.join(room);
      socket.data.activeGuestBookingId = status.bookingId;
      socket.data.activeGuestBookingNumber = bookingNumber;

      const response = { room, bookingId: status.bookingId, status };
      socket.emit('booking:urgent-negotiation:subscribed', response);
      if (typeof ack === 'function') ack({ ok: true, ...response });
    } catch (err) {
      const mapped = {
        code: err.errorCode ?? ERROR_CODES.INTERNAL_SERVER_ERROR,
        message: err.message ?? 'Urgent negotiation subscription failed',
      };
      socket.emit('booking:urgent-negotiation:error', mapped);
      if (typeof ack === 'function') ack({ ok: false, error: mapped });
    }
  });

  socket.on('booking:urgent-negotiation:unsubscribe', async (_payload = {}, ack) => {
    const bookingId = socket.data.activeGuestBookingId;
    if (bookingId) {
      await socket.leave(guestBookingRoom(bookingId));
      socket.data.activeGuestBookingId = null;
      socket.data.activeGuestBookingNumber = null;
    }
    if (typeof ack === 'function') ack({ ok: true });
  });
}

module.exports = {
  registerBookingHandlers,
};
