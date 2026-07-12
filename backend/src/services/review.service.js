const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');
const MODERATION_STATUS = require('../constants/reviewModerationStatus');
const { normalizeTags, parseStoredTags } = require('../constants/reviewTags');
const { hashToken } = require('../utils/tokenHash.util');
const { randomUUID } = require('node:crypto');
const { EVENTS } = require('../events');

const MAX_COMMENT_LENGTH = 500;
const BOOKING_STATUS = {
  SETTLEMENT_PENDING: 'SETTLEMENT_PENDING',
  COMPLETED: 'COMPLETED',
  CANCELLED: 'CANCELLED',
  NO_SHOW: 'NO_SHOW',
};
const REVIEW_ELIGIBLE_STATUSES = new Set([
  BOOKING_STATUS.SETTLEMENT_PENDING,
  BOOKING_STATUS.COMPLETED,
]);

class ReviewService {
  constructor(
    pool,
    bookingRepository,
    reviewRepository,
    driverRepository,
    bookingService,
    outboxRepository,
    outboxProcessor,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.reviewRepository = reviewRepository;
    this.driverRepository = driverRepository;
    this.bookingService = bookingService;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
  }

  formatDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  parsePagination(query) {
    const page = Number(query.page) || 1;
    const limit = Number(query.limit ?? query.page_size) || 20;
    const safeLimit = Math.min(Math.max(limit, 1), 100);
    const offset = (Math.max(page, 1) - 1) * safeLimit;
    return { page: Math.max(page, 1), limit: safeLimit, offset };
  }

  parseAdminFilters(query) {
    const filters = {
      rating: query.rating ? Number(query.rating) : null,
      status: query.status || null,
      driverId: query.driverId ? Number(query.driverId) : null,
      bookingNumber: query.bookingNumber?.trim().toUpperCase() || null,
      search: query.search?.trim() || null,
      dateFrom: null,
      dateTo: null,
    };
    if (query.dateFrom) {
      filters.dateFrom = `${query.dateFrom} 00:00:00`;
    }
    if (query.dateTo) {
      const end = new Date(`${query.dateTo}T00:00:00`);
      end.setDate(end.getDate() + 1);
      filters.dateTo = end.toISOString().slice(0, 19).replace('T', ' ');
    }
    return filters;
  }

  assertNotStaffSubmitter(authUser) {
    if (!authUser) return;
    if ([ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN].includes(authUser.role)) {
      throw new AppError('Forbidden', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.FORBIDDEN,
      });
    }
  }

  resolveDriverId(booking) {
    if (!booking.driver_id) {
      throw new AppError('Review is not eligible for this booking', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.REVIEW_NOT_ELIGIBLE,
      });
    }
    return booking.driver_id;
  }

  isReviewEligible(booking) {
    if (!booking?.driver_id) return false;
    if (booking.status === BOOKING_STATUS.CANCELLED || booking.status === BOOKING_STATUS.NO_SHOW) {
      return false;
    }
    return REVIEW_ELIGIBLE_STATUSES.has(booking.status);
  }

  assertReviewEligible(booking) {
    if (!this.isReviewEligible(booking)) {
      throw new AppError('Review is not eligible for this booking', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.REVIEW_NOT_ELIGIBLE,
      });
    }
  }

  mapReviewRecord(review) {
    if (!review) return null;
    return {
      rating: review.rating,
      tags: parseStoredTags(review.tags_json),
      comment: review.comment,
      createdAt: review.created_at,
      moderationStatus: review.moderation_status,
      lowRating: Number(review.rating) <= 2,
    };
  }

  mapCustomerReviewState(booking, review) {
    const eligible = this.isReviewEligible(booking);
    if (!review) {
      return {
        eligible,
        submitted: false,
        rating: null,
        tags: [],
        comment: null,
        createdAt: null,
      };
    }
    const mapped = this.mapReviewRecord(review);
    return {
      eligible,
      submitted: true,
      rating: mapped.rating,
      tags: mapped.tags,
      comment: mapped.comment,
      createdAt: mapped.createdAt,
      moderationStatus: mapped.moderationStatus,
    };
  }

  mapAdminReviewSummary(review) {
    if (!review) return null;
    const mapped = this.mapReviewRecord(review);
    return {
      reviewId: review.id,
      rating: mapped.rating,
      tags: mapped.tags,
      comment: mapped.comment,
      createdAt: mapped.createdAt,
      lowRating: mapped.lowRating,
      moderationStatus: mapped.moderationStatus,
    };
  }

  mapAdminListItem(row) {
    return {
      reviewId: row.id,
      bookingNumber: row.booking_number,
      driver: {
        driverId: row.driver_id,
        displayName: row.driver_name,
      },
      customerDisplayName: row.customer_user_id
        ? (row.customer_name || 'Customer')
        : 'Guest',
      rating: row.rating,
      tags: parseStoredTags(row.tags_json),
      comment: row.comment,
      lowRating: Number(row.rating) <= 2,
      moderationStatus: row.moderation_status,
      createdAt: row.created_at,
    };
  }

  mapAdminDetail(row, moderationHistory) {
    return {
      reviewId: row.id,
      rating: row.rating,
      tags: parseStoredTags(row.tags_json),
      comment: row.comment,
      lowRating: Number(row.rating) <= 2,
      moderationStatus: row.moderation_status,
      hiddenReason: row.hidden_reason,
      reviewedAt: row.reviewed_at,
      createdAt: row.created_at,
      bookingSummary: {
        bookingNumber: row.booking_number,
        status: row.booking_status,
        completedAt: row.completed_at,
        totalAmount: row.total_amount != null ? Number(row.total_amount) : null,
        currency: row.currency,
      },
      driverSummary: {
        driverId: row.driver_id,
        displayName: row.driver_name,
        phone: row.driver_phone,
      },
      customerSummary: row.customer_user_id
        ? { customerUserId: row.customer_user_id, displayName: row.customer_name || 'Customer' }
        : { displayName: 'Guest' },
      moderationHistory: moderationHistory.map((entry) => ({
        activityType: entry.activity_type,
        actorUserId: entry.actor_user_id,
        actorRole: entry.actor_role,
        description: entry.description,
        createdAt: entry.created_at,
      })),
    };
  }

  async getBookingReview(bookingNumber, authUser, guestAccessToken) {
    this.assertNotStaffSubmitter(authUser);
    const normalized = this.bookingService.validateBookingNumber(bookingNumber);
    const booking = await this.bookingRepository.findByBookingNumber(normalized);
    if (!booking) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    const conn = await this.pool.getConnection();
    try {
      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );
    } finally {
      conn.release();
    }

    const review = await this.reviewRepository.findByBookingId(booking.id);
    return this.mapCustomerReviewState(booking, review);
  }

  validateRating(rating) {
    const value = Number(rating);
    if (!Number.isInteger(value) || value < 1 || value > 5) {
      throw new AppError('Rating must be an integer from 1 to 5', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_RATING,
      });
    }
    return value;
  }

  normalizeComment(comment) {
    if (comment == null || comment === '') return null;
    if (typeof comment !== 'string') {
      throw new AppError('Comment must be a string', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    const trimmed = comment.trim();
    if (!trimmed) return null;
    if (trimmed.length > MAX_COMMENT_LENGTH) {
      throw new AppError(`Comment must be at most ${MAX_COMMENT_LENGTH} characters`, {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return trimmed;
  }

  normalizeTags(input, rating) {
    return normalizeTags(input, rating);
  }

  async submitBookingReview(bookingNumber, input, authUser) {
    this.assertNotStaffSubmitter(authUser);
    const normalized = this.bookingService.validateBookingNumber(bookingNumber);
    const rating = this.validateRating(input.rating);
    const comment = this.normalizeComment(input.comment);
    const tags = this.normalizeTags(input.tags, rating);

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        normalized,
      );
      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        input.guestAccessToken,
      );

      this.assertReviewEligible(booking);

      const driverId = this.resolveDriverId(booking);
      const existing = await this.reviewRepository.findByBookingIdForUpdate(conn, booking.id);
      if (existing) {
        throw new AppError('Review already submitted for this booking', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.REVIEW_ALREADY_SUBMITTED,
        });
      }

      let guestAccessTokenId = null;
      if (!authUser || authUser.role !== ROLES.CUSTOMER) {
        const guestToken = await this.bookingRepository.findActiveGuestTokenForBooking(
          conn,
          booking.id,
          hashToken(String(input.guestAccessToken ?? '').trim()),
        );
        guestAccessTokenId = guestToken?.id ?? null;
      }

      const customerUserId = authUser?.role === ROLES.CUSTOMER ? authUser.id : null;
      const reviewId = await this.reviewRepository.insert(conn, {
        bookingId: booking.id,
        driverId,
        customerUserId,
        guestAccessTokenId,
        rating,
        comment,
        tags,
        moderationStatus: MODERATION_STATUS.VISIBLE,
      });

      await this.bookingRepository.insertActivityLog(conn, booking.id, {
        activityType: 'REVIEW_SUBMITTED',
        actorUserId: customerUserId,
        actorRole: ROLES.CUSTOMER,
        description: `Review submitted for ${normalized}`,
        payload: { bookingNumber: normalized, reviewId, rating, tags },
      });

      let outboxId = null;
      if (this.outboxRepository) {
        outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
          aggregateId: booking.id,
          eventType: EVENTS.REVIEW_SUBMITTED,
          payload: {
            eventId: randomUUID(),
            eventName: EVENTS.REVIEW_SUBMITTED,
            bookingId: booking.id,
            bookingNumber: normalized,
          },
        });
      }

      await conn.commit();

      if (outboxId && this.outboxProcessor) {
        await this.outboxProcessor.dispatchOutboxIds([outboxId]);
      }

      const review = await this.reviewRepository.findByBookingId(booking.id);
      return this.mapCustomerReviewState(booking, review);
    } catch (err) {
      await conn.rollback();
      if (err.code === 'ER_DUP_ENTRY') {
        throw new AppError('Review already submitted for this booking', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.REVIEW_ALREADY_SUBMITTED,
        });
      }
      throw err;
    } finally {
      conn.release();
    }
  }

  async getDriverRatingSummary(driverUserId) {
    const driver = await this.driverRepository.findByUserId(driverUserId);
    if (!driver) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    return this.reviewRepository.getVisibleRatingSummaryForDriver(driver.id);
  }

  async listAdminReviews(query) {
    const filters = this.parseAdminFilters(query);
    const pagination = this.parsePagination(query);
    const total = await this.reviewRepository.countAdminReviews(filters);
    const rows = await this.reviewRepository.findAdminReviews(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.limit,
      total,
      items: rows.map((row) => this.mapAdminListItem(row)),
    };
  }

  async getAdminReview(reviewId) {
    const row = await this.reviewRepository.findById(reviewId);
    if (!row) {
      throw new AppError('Review not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.REVIEW_NOT_FOUND,
      });
    }
    const moderationHistory = await this.reviewRepository.findModerationActivityLogs(row.booking_id);
    return this.mapAdminDetail(row, moderationHistory);
  }

  async hideReview(reviewId, reason, user) {
    const trimmedReason = String(reason ?? '').trim();
    if (!trimmedReason) {
      throw new AppError('Reason is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.REVIEW_REASON_REQUIRED,
      });
    }

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const row = await this.reviewRepository.findByIdForUpdate(conn, reviewId);
      if (!row) {
        throw new AppError('Review not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.REVIEW_NOT_FOUND,
        });
      }

      if (row.moderation_status === MODERATION_STATUS.HIDDEN) {
        if (row.hidden_reason === trimmedReason) {
          await conn.commit();
          return this.getAdminReview(reviewId);
        }
        throw new AppError('Review is already hidden', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.REVIEW_ALREADY_HIDDEN,
        });
      }

      const reviewedAt = this.formatDateTime(new Date());
      await this.reviewRepository.updateModeration(conn, reviewId, {
        moderationStatus: MODERATION_STATUS.HIDDEN,
        hiddenReason: trimmedReason,
        reviewedBy: user.id,
        reviewedAt,
      });

      await this.bookingRepository.insertActivityLog(conn, row.booking_id, {
        activityType: 'REVIEW_HIDDEN',
        actorUserId: user.id,
        actorRole: user.role,
        description: `Review hidden for ${row.booking_number}`,
        payload: { reviewId, reason: trimmedReason },
      });

      await conn.commit();
      return this.getAdminReview(reviewId);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async restoreReview(reviewId, user) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const row = await this.reviewRepository.findByIdForUpdate(conn, reviewId);
      if (!row) {
        throw new AppError('Review not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.REVIEW_NOT_FOUND,
        });
      }

      if (row.moderation_status === MODERATION_STATUS.VISIBLE) {
        await conn.commit();
        return this.getAdminReview(reviewId);
      }

      const reviewedAt = this.formatDateTime(new Date());
      await this.reviewRepository.updateModeration(conn, reviewId, {
        moderationStatus: MODERATION_STATUS.VISIBLE,
        hiddenReason: null,
        reviewedBy: user.id,
        reviewedAt,
      });

      await this.bookingRepository.insertActivityLog(conn, row.booking_id, {
        activityType: 'REVIEW_RESTORED',
        actorUserId: user.id,
        actorRole: user.role,
        description: `Review restored for ${row.booking_number}`,
        payload: { reviewId },
      });

      await conn.commit();
      return this.getAdminReview(reviewId);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = ReviewService;
