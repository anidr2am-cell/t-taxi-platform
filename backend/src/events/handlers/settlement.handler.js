const { appEvents, EVENTS } = require('..');
const logger = require('../../utils/logger');
const container = require('../../helpers/container');

function registerSettlementHandlers() {
  appEvents.on(EVENTS.TRIP_COMPLETED, async (payload) => {
    try {
      const service = container.get('commissionSettlementService');
      await service.activateObligationForCompletedBooking(payload.bookingId);
    } catch (err) {
      logger.error('Commission obligation activation failed', {
        bookingId: payload?.bookingId,
        bookingNumber: payload?.bookingNumber,
        err,
      });
    }
  });
}

module.exports = { registerSettlementHandlers };
