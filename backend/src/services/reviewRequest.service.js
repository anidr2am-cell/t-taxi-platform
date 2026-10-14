const AppError = require('../utils/AppError');
const { LOCALES, CHANNELS, parseMetadata, reviewRequestState } = require('../utils/reviewRequest.util');

// Manual tracking only. This service deliberately has no notification/outbox dependency.
class ReviewRequestService {
  constructor(pool, bookingRepository, platformSettingsService) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.platformSettingsService = platformSettingsService;
  }

  async get(bookingNumber) {
    const conn = await this.pool.getConnection();
    try {
      const booking = await this.bookingRepository.findByBookingNumberForUpdate(conn, bookingNumber);
      if (!booking) throw new AppError('Booking not found', { statusCode: 404, errorCode: 'BOOKING_NOT_FOUND' });
      return { ...reviewRequestState(booking), googleReviewUrl: (await this.platformSettingsService.getPublic()).googleReviewUrl || '' };
    } finally { conn.release(); }
  }

  async update(bookingNumber, input, actor) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const booking = await this.bookingRepository.findByBookingNumberForUpdate(conn, bookingNumber);
      if (!booking) throw new AppError('Booking not found', { statusCode: 404, errorCode: 'BOOKING_NOT_FOUND' });
      const state = reviewRequestState(booking);
      const fail = (code) => { throw new AppError(code, { statusCode: 409, errorCode: code }); };
      if (!state.eligible) fail('REVIEW_NOT_ELIGIBLE');
      if (!['COPY', 'SENT', 'OPT_OUT'].includes(input.action)) fail('INVALID_REVIEW_REQUEST_ACTION');
      if (input.action !== 'OPT_OUT' && state.optedOut) fail('REVIEW_REQUEST_OPTED_OUT');
      if (input.action !== 'OPT_OUT' && !LOCALES.includes(input.locale)) fail('REVIEW_REQUEST_LOCALE_REQUIRED');
      if (input.action === 'SENT' && !CHANNELS.includes(input.channel)) fail('REVIEW_REQUEST_CHANNEL_REQUIRED');
      if (input.action === 'SENT' && state.sentAt && input.confirmResend !== true) fail('REVIEW_REQUEST_ALREADY_SENT');
      const metadata = parseMetadata(booking.metadata);
      const request = { ...(metadata.reviewRequest || {}) };
      const now = new Date().toISOString();
      if (input.action === 'COPY') request.copiedAt = now;
      if (input.action === 'SENT') {
        request.sentAt = now;
        request.channel = input.channel;
        request.actorUserId = actor.id;
        request.actorName = actor.name || actor.email || String(actor.id);
      }
      if (input.action === 'OPT_OUT') request.optedOut = input.optedOut === true;
      else request.locale = input.locale;
      metadata.reviewRequest = request;
      await this.bookingRepository.updateCommissionFields(conn, booking.id, { metadata });
      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: `REVIEW_REQUEST_${input.action}`,
        actorUserId: actor.id, actorRole: actor.role,
        description: `Manual review request: ${input.action}`,
        payload: { ...request, occurredAt: now },
      });
      await conn.commit();
      return reviewRequestState({ ...booking, metadata });
    } catch (error) { await conn.rollback(); throw error; }
    finally { conn.release(); }
  }
}
module.exports = ReviewRequestService;
