class CustomerBookingService {
  constructor(bookingRepository, guestBookingLookupService, reviewRepository = null) {
    this.bookingRepository = bookingRepository;
    this.guestBookingLookupService = guestBookingLookupService;
    this.reviewRepository = reviewRepository;
  }

  normalizePagination(query = {}) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit ?? query.page_size) || 20, 1), 100);
    const offset = (page - 1) * limit;
    return { page, limit, offset };
  }

  async listMyBookings(userId, query = {}) {
    const pagination = this.normalizePagination(query);
    const [rows, total] = await Promise.all([
      this.bookingRepository.findByCustomerUserId(userId, pagination),
      this.bookingRepository.countByCustomerUserId(userId),
    ]);

    const reviewsByBookingId = new Map();
    if (this.reviewRepository && rows.length > 0) {
      await Promise.all(
        rows.map(async (row) => {
          const review = await this.reviewRepository.findByBookingId(row.id);
          if (review) {
            reviewsByBookingId.set(row.id, review);
          }
        }),
      );
    }

    const bookings = rows.map((row) => this.guestBookingLookupService.mapBooking(
      row,
      null,
      null,
      reviewsByBookingId.get(row.id) ?? null,
    ));

    return {
      bookings,
      total,
      page: pagination.page,
      limit: pagination.limit,
    };
  }

  async getBookingStatusCounts(userId) {
    return this.bookingRepository.countStatusGroupsByCustomerUserId(userId);
  }
}

module.exports = CustomerBookingService;
