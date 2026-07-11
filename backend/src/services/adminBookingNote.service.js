const AppError = require('../utils/AppError');
const ERROR_CODES = require('../constants/errorCodes');
const HTTP_STATUS = require('../constants/httpStatus');

class AdminBookingNoteService {
  constructor(pool, noteRepository, bookingRepository) {
    this.pool = pool;
    this.noteRepository = noteRepository;
    this.bookingRepository = bookingRepository;
  }

  assertAdmin(actor) {
    if (!actor || !['ADMIN', 'SUPER_ADMIN'].includes(actor.role)) {
      throw new AppError('Admin access required', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.FORBIDDEN,
      });
    }
  }

  async requireBooking(bookingNumber) {
    const booking = await this.noteRepository.findBookingByNumber(bookingNumber);
    if (!booking) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }
    return booking;
  }

  mapNote(row) {
    return {
      id: row.id,
      text: row.note_text,
      author: { id: row.admin_user_id, name: row.author_name },
      createdAt: row.created_at,
    };
  }

  async list(bookingNumber, query, actor) {
    this.assertAdmin(actor);
    const booking = await this.requireBooking(bookingNumber);
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 50);
    const offset = (page - 1) * limit;
    const [rows, total] = await Promise.all([
      this.noteRepository.listByBookingId(booking.id, { limit, offset }),
      this.noteRepository.countByBookingId(booking.id),
    ]);
    return { page, pageSize: limit, total, items: rows.map((row) => this.mapNote(row)) };
  }

  async create(bookingNumber, input, actor) {
    this.assertAdmin(actor);
    const booking = await this.requireBooking(bookingNumber);
    const text = input.text.trim();
    const conn = await this.pool.getConnection();
    let noteId;
    try {
      await conn.beginTransaction();
      noteId = await this.noteRepository.insert(conn, {
        bookingId: booking.id,
        adminUserId: actor.id,
        text,
      });
      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'ADMIN_BOOKING_NOTE_ADDED',
        actorUserId: actor.id,
        actorRole: actor.role,
        description: 'Administrator added an internal booking note',
        payload: { bookingNumber, noteId },
      });
      await conn.commit();
    } catch (error) {
      await conn.rollback();
      throw error;
    } finally {
      conn.release();
    }
    return this.mapNote(await this.noteRepository.findById(noteId));
  }
}

module.exports = AdminBookingNoteService;
