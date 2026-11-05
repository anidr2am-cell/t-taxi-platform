const { resolveBookingAirport } = require('../utils/bookingAirport.util');
const { createHash } = require('node:crypto');
const GateArrivalRepository = require('../repositories/customerGateArrival.repository');
const AppError = require('../utils/AppError');
const { parseServiceDateTimeToMs } = require('../utils/serviceDateTime.util');
const ALLOWED = new Set(['DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED']);
const fail = (code, statusCode = 409) => { throw new AppError(code, { errorCode: code, statusCode }); };

// Use the existing durable notification queue, serialized with assignment changes.
class CustomerGateArrivalService {
  constructor(pool, bookingRepository, bookingService, notificationService) {
    Object.assign(this, { pool, bookingRepository, bookingService, notificationService });
    this.arrivalRepository = new GateArrivalRepository();
  }
  async run(bookingNumber, user, token, send = false) {
    const conn = await this.pool.getConnection();
    let notificationId;
    try {
      await conn.beginTransaction();
      const b = await this.bookingRepository.findByBookingNumberForUpdate(conn, bookingNumber);
      if (!b) fail('BOOKING_NOT_FOUND', 404);
      await this.bookingService.assertCustomerOrGuestAccess(conn, b, user, token);
      const transfer = await this.bookingRepository.findTransferByBookingId(conn, b.id);
      const hasNameSign = await this.arrivalRepository.hasNameSign(conn, b.id);
      const airport = await resolveBookingAirport({ ...b, airport_iata: transfer?.airport_iata, airport_code_custom: transfer?.airport_code_custom }, this.bookingRepository, conn);
      if (b.service_type_code !== 'AIRPORT_PICKUP' || airport !== 'BKK' || hasNameSign) {
        fail('GATE_ARRIVAL_NOT_APPLICABLE');
      }
      const a = await this.arrivalRepository.findActiveAssignment(conn, b.id);
      const available = ALLOWED.has(b.status) && a && a.status !== 'SUSPENDED';
      const pickupMs = parseServiceDateTimeToMs(b.scheduled_pickup_at);
      const inWindow = pickupMs != null && Math.abs(Date.now() - pickupMs) <= 86400000;
      const key = a ? `gate-arrival:${b.id}:${a.id}` : null;
      let existing = key ? await this.notificationService.notificationRepository.findByIdempotencyKey(conn, key) : null;
      if (send) {
        if (!available) fail('GATE_ARRIVAL_DRIVER_UNAVAILABLE');
        if (!inWindow) fail('GATE_ARRIVAL_OUTSIDE_PICKUP_WINDOW');
        if (!existing) {
          const result = await this.notificationService.persistDirectNotificationTx(conn, {
            recipientType: 'USER', userId: a.user_id, recipientDriverId: a.driver_id,
            bookingId: b.id, audienceRole: 'DRIVER', notificationType: 'CUSTOMER_GATE_ARRIVED',
            eventId: createHash('sha256').update(key).digest('hex').slice(0,36), eventName: 'customer.gate_arrived', idempotencyKey: key,
            payload: { bookingNumber: b.booking_number, gate: '7', airport: 'BKK', assignmentId: a.id },
          }, { contentOverride: {
            title: 'ลูกค้าถึงประตู 7 แล้ว',
            body: `การจอง ${b.booking_number}: ลูกค้ารับกระเป๋าครบแล้ว และรออยู่ด้านนอกประตู 7 ชั้นผู้โดยสารขาเข้า สนามบินสุวรรณภูมิ โปรดเปิดรายละเอียดงานและประสานจุดรับกับผู้ดูแล`,
          }});
          notificationId = result.notificationId;
          existing = { id: notificationId, read_at: null };
        }
      }
      await conn.commit();
      // A push failure cannot undo a committed arrival or ask the customer to resend.
      if (notificationId) await this.notificationService.processDeliveries(notificationId).catch(() => {});
      return { available: Boolean(available && inWindow), gate: '7', airport: 'BKK',
        sent: Boolean(existing), notificationRead: Boolean(existing?.read_at) };
    } catch (error) {
      await conn.rollback();
      throw error;
    } finally { conn.release(); }
  }
}
module.exports = CustomerGateArrivalService;
