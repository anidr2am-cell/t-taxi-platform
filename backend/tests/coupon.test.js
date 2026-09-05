process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const CouponService = require('../src/services/coupon.service');
const CouponRepository = require('../src/repositories/coupon.repository');
const BookingService = require('../src/services/booking.service');
const { computeAccrualAmount } = require('../src/services/mileage.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const COUPON_STATUS = require('../src/constants/couponStatus');
const { setRealtimeIo } = require('../src/socket/realtime');

const CUSTOMER_ID = 42;
const ADMIN_ID = 7;

function registerCustomerAuth(userId = CUSTOMER_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: 'CUSTOMER', email: 'customer@test.local' };
    },
  }));
}

function registerAdminAuth(userId = ADMIN_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: 'ADMIN', email: 'admin@test.local' };
    },
  }));
}

describe('CouponService.buildCouponChargeItem', () => {
  test('clamps discount to subtotal and emits negative COUPON charge item', () => {
    const service = new CouponService({}, {});
    const item = service.buildCouponChargeItem(
      { id: 5, title: 'Welcome 500', discount_amount: 500 },
      300,
    );

    assert.equal(item.chargeType, 'COUPON');
    assert.equal(item.amount, -300);
    assert.equal(item.unitPrice, -300);
    assert.equal(item.referenceType, 'COUPON');
    assert.equal(item.referenceId, 5);
    assert.equal(item.description, 'Welcome 500');
  });

  test('returns null when subtotal is zero', () => {
    const service = new CouponService({}, {});
    const item = service.buildCouponChargeItem(
      { id: 5, title: 'Welcome 500', discount_amount: 500 },
      0,
    );
    assert.equal(item, null);
  });
});

describe('CouponService.markCouponUsed', () => {
  test('throws when coupon was already consumed concurrently', async () => {
    const couponRepository = {
      async markUsed() {
        return 0;
      },
    };
    const service = new CouponService(couponRepository, {});

    await assert.rejects(
      () => service.markCouponUsed({}, 9, 100, CUSTOMER_ID),
      (err) => err.message === '이미 사용됐거나 유효하지 않은 쿠폰입니다',
    );
  });
});

describe('CouponService.issueCoupon and cancelCoupon', () => {
  test('issues AVAILABLE coupon for existing customer', async () => {
    const pool = {
      async getConnection() {
        return {
          async beginTransaction() {},
          async commit() {},
          async rollback() {},
          release() {},
        };
      },
    };
    const couponRepository = {
      async findCustomerById(id) {
        return id === 10 ? { id: 10, role: 'CUSTOMER' } : null;
      },
      async insertCoupon(_conn, payload) {
        assert.equal(payload.customerUserId, 10);
        assert.equal(payload.discountAmount, 200);
        return 55;
      },
      async findById(id) {
        return {
          id,
          title: 'Promo',
          discount_amount: 200,
          status: COUPON_STATUS.AVAILABLE,
          issued_at: '2026-09-01 10:00:00',
          used_at: null,
          used_booking_id: null,
        };
      },
    };
    const service = new CouponService(couponRepository, pool);
    const coupon = await service.issueCoupon({
      customerUserId: 10,
      title: 'Promo',
      discountAmount: 200,
      issuedByAdminId: ADMIN_ID,
    });

    assert.equal(coupon.id, 55);
    assert.equal(coupon.discountAmount, 200);
    assert.equal(coupon.status, COUPON_STATUS.AVAILABLE);
  });

  test('cancelCoupon rejects USED coupons', async () => {
    const couponRepository = {
      async findById() {
        return { id: 1, status: COUPON_STATUS.USED };
      },
    };
    const service = new CouponService(couponRepository, {});

    await assert.rejects(
      () => service.cancelCoupon(1),
      (err) => err.errorCode === 'COUPON_ALREADY_USED',
    );
  });
});

const SERVER_PRICE = {
  routeId: 7,
  currency: 'THB',
  subtotal: 1400,
  totalAmount: 1400,
  chargeItems: [
    {
      chargeType: 'VEHICLE_BASE',
      description: 'SUV AIRPORT_PICKUP',
      quantity: 1,
      unitPrice: 1400,
      amount: 1400,
      referenceType: 'VEHICLE_PRICE',
      referenceId: 99,
    },
  ],
};

const CREATE_INPUT = {
  bookingMode: 'STANDARD',
  serviceTypeCode: 'AIRPORT_PICKUP',
  vehicleTypeCode: 'SUV',
  vehicleCount: 1,
  scheduledPickupAt: '2026-12-01T02:30:00.000Z',
  originAirportIata: 'BKK',
  destinationLocationCode: 'PATTAYA',
  origin: {
    name: 'Suvarnabhumi Airport',
    address: '999 Moo 1, Samut Prakan, Thailand',
    placeId: 'google-bkk',
    lat: 13.69,
    lng: 100.75,
  },
  destination: {
    name: 'Pattaya Hotel',
    address: 'Pattaya, Chon Buri, Thailand',
    placeId: 'google-pattaya',
    lat: 12.92,
    lng: 100.88,
  },
  passengers: { adults: 2, children: 0, infants: 0 },
  luggage: {},
  options: {},
  transfer: { airportIata: 'BKK' },
  customer: {
    name: 'Kim Test',
    phone: '+66123456789',
  },
};

function createBookingHarness({ couponService, authUser = { id: CUSTOMER_ID, role: 'CUSTOMER' }, conn } = {}) {
  const calls = {
    chargeItems: [],
    markUsed: [],
    booking: null,
  };
  const resolvedConn = conn ?? {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };

  const bookingRepository = {
    async insertBooking(_conn, row) {
      calls.booking = row;
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage() {},
    async insertTransferDetails() {},
    async insertChargeItem(_conn, bookingId, item) {
      calls.chargeItems.push({ bookingId, ...item });
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
    async insertGuestToken() {},
    async findAirportByIata() {
      return { id: 1, iata_code: 'BKK' };
    },
    async findById() {
      const couponItem = calls.chargeItems.find((item) => item.chargeType === 'COUPON');
      const discount = couponItem ? Math.abs(Number(couponItem.amount)) : 0;
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: BOOKING_STATUS.OPEN,
        scheduled_pickup_at: CREATE_INPUT.scheduledPickupAt,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: SERVER_PRICE.totalAmount - discount,
        currency: 'THB',
      };
    },
  };

  const resolvedCouponService = couponService ?? {
    assertCouponAuthRequired() {},
    async resolveAvailableCoupon() {
      return {
        id: 3,
        title: '500 OFF',
        discount_amount: 500,
      };
    },
    buildCouponChargeItem(coupon, subtotal) {
      const applied = Math.min(coupon.discount_amount, subtotal);
      return applied > 0
        ? {
          chargeType: 'COUPON',
          description: coupon.title,
          quantity: 1,
          unitPrice: -applied,
          amount: -applied,
          referenceType: 'COUPON',
          referenceId: coupon.id,
        }
        : null;
    },
    async markCouponUsed(_conn, couponId, bookingId, userId) {
      calls.markUsed.push({ couponId, bookingId, userId });
      return 1;
    },
  };

  const service = new BookingService(
    { async getConnection() { return resolvedConn; } },
    bookingRepository,
    { async generateNext() { return 'TX202607130001'; } },
    {
      async calculate() { return SERVER_PRICE; },
      async resolveServiceType() {
        return { id: 1, code: 'AIRPORT_PICKUP', name: 'Airport Pickup' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'SUV' }; } },
    { async findTypeByCode() { return { id: 2, code: 'SUV', name: 'SUV' }; } },
    {
      async insertNotificationEvent() { return 30; },
    },
    { async dispatchOutboxIds() {} },
    null,
    { async listEligibleForOpenBooking() { return []; } },
    null,
    null,
    null,
    null,
    null,
    resolvedCouponService,
  );

  setRealtimeIo({ to() { return { emit() {} }; } });

  return { service, calls, authUser };
}

describe('BookingService.createBooking with coupon', () => {
  test('rejects coupon usage for guest bookings', async () => {
    const { service } = createBookingHarness({
      authUser: null,
      couponService: {
        assertCouponAuthRequired(couponId, authUser) {
          if (couponId != null && !authUser) {
            const AppError = require('../src/utils/AppError');
            const HTTP_STATUS = require('../src/constants/httpStatus');
            const ERROR_CODES = require('../src/constants/errorCodes');
            throw new AppError('Login is required to use a coupon', {
              statusCode: HTTP_STATUS.UNAUTHORIZED,
              errorCode: ERROR_CODES.COUPON_AUTH_REQUIRED,
            });
          }
        },
      },
    });

    await assert.rejects(
      () => service.createBooking({ ...CREATE_INPUT, couponId: 3 }, null),
      (err) => err.errorCode === 'COUPON_AUTH_REQUIRED',
    );
  });

  test('adds COUPON charge item, marks coupon used, and accrual uses discounted total', async () => {
    const { service, calls, authUser } = createBookingHarness();
    const result = await service.createBooking(
      { ...CREATE_INPUT, couponId: 3 },
      authUser,
    );

    const couponItem = calls.chargeItems.find((item) => item.chargeType === 'COUPON');
    assert.ok(couponItem);
    assert.equal(couponItem.amount, -500);
    assert.equal(couponItem.referenceType, 'COUPON');
    assert.equal(couponItem.referenceId, 3);
    assert.deepEqual(calls.markUsed, [{
      couponId: 3,
      bookingId: 10,
      userId: CUSTOMER_ID,
    }]);
    assert.equal(result.data.totalAmount, 900);
    assert.equal(computeAccrualAmount(result.data.totalAmount), 45);
  });

  test('clamps coupon discount to subtotal in charge item', async () => {
    const { service, calls } = createBookingHarness({
      couponService: {
        assertCouponAuthRequired() {},
        async resolveAvailableCoupon() {
          return { id: 8, title: 'Huge', discount_amount: 2000 };
        },
        buildCouponChargeItem(coupon, subtotal) {
          const applied = Math.min(coupon.discount_amount, subtotal);
          return {
            chargeType: 'COUPON',
            description: coupon.title,
            quantity: 1,
            unitPrice: -applied,
            amount: -applied,
            referenceType: 'COUPON',
            referenceId: coupon.id,
          };
        },
        async markCouponUsed() { return 1; },
      },
    });

    await service.createBooking(
      { ...CREATE_INPUT, couponId: 8 },
      { id: CUSTOMER_ID, role: 'CUSTOMER' },
    );

    const couponItem = calls.chargeItems.find((item) => item.chargeType === 'COUPON');
    assert.equal(couponItem.amount, -1400);
  });

  test('rolls back when concurrent coupon consumption fails', async () => {
    let rolledBack = false;
    const conn = {
      async beginTransaction() {},
      async commit() {
        throw new Error('commit should not run');
      },
      async rollback() {
        rolledBack = true;
      },
      release() {},
    };

    const { service } = createBookingHarness({
      conn,
      couponService: {
        assertCouponAuthRequired() {},
        async resolveAvailableCoupon() {
          return { id: 4, title: 'Race', discount_amount: 100 };
        },
        buildCouponChargeItem() {
          return {
            chargeType: 'COUPON',
            description: 'Race',
            quantity: 1,
            unitPrice: -100,
            amount: -100,
            referenceType: 'COUPON',
            referenceId: 4,
          };
        },
        async markCouponUsed() {
          const AppError = require('../src/utils/AppError');
          throw new AppError('이미 사용됐거나 유효하지 않은 쿠폰입니다', {
            statusCode: 409,
            errorCode: 'COUPON_NOT_AVAILABLE',
          });
        },
      },
    });

    await assert.rejects(
      () => service.createBooking(
        { ...CREATE_INPUT, couponId: 4 },
        { id: CUSTOMER_ID, role: 'CUSTOMER' },
      ),
      (err) => err.message === '이미 사용됐거나 유효하지 않은 쿠폰입니다',
    );
    assert.equal(rolledBack, true);
  });
});

describe('Customer coupon API', () => {
  test('GET /api/v1/customer/coupons returns owned coupons with booking numbers', async () => {
    registerCustomerAuth();

    container.register('couponService', () => ({
      async listCouponsForCustomer(userId) {
        assert.equal(userId, CUSTOMER_ID);
        return [{
          id: 1,
          title: 'Welcome',
          discountAmount: 200,
          status: COUPON_STATUS.USED,
          issuedAt: '2026-09-01T10:00:00+07:00',
          usedAt: '2026-09-02T12:00:00+07:00',
          usedBookingId: 99,
          bookingNumber: 'TX202609020001',
        }];
      },
    }));

    const response = await request(app)
      .get('/api/v1/customer/coupons')
      .set('Authorization', 'Bearer test-token');

    assert.equal(response.statusCode, 200);
    assert.equal(response.body.data.length, 1);
    assert.equal(response.body.data[0].bookingNumber, 'TX202609020001');
  });
});

describe('Admin coupon API', () => {
  test('GET /api/v1/admin/customers/search requires admin auth', async () => {
    registerCustomerAuth();
    const response = await request(app)
      .get('/api/v1/admin/customers/search')
      .query({ query: 'kim' })
      .set('Authorization', 'Bearer test-token');
    assert.equal(response.statusCode, 403);
  });

  test('POST /api/v1/admin/coupons issues coupon', async () => {
    registerAdminAuth();

    container.register('couponService', () => ({
      async issueCoupon(payload) {
        assert.equal(payload.customerUserId, 10);
        assert.equal(payload.discountAmount, 300);
        assert.equal(payload.issuedByAdminId, ADMIN_ID);
        return {
          id: 12,
          title: 'VIP',
          discountAmount: 300,
          status: COUPON_STATUS.AVAILABLE,
          issuedAt: '2026-09-01T10:00:00+07:00',
          usedAt: null,
          usedBookingId: null,
          bookingNumber: null,
        };
      },
    }));

    const response = await request(app)
      .post('/api/v1/admin/coupons')
      .set('Authorization', 'Bearer admin-token')
      .send({
        customerUserId: 10,
        title: 'VIP',
        discountAmount: 300,
      });

    assert.equal(response.statusCode, 201);
    assert.equal(response.body.data.id, 12);
  });
});

describe('CouponRepository.searchCustomers SQL contract', () => {
  test('filters CUSTOMER role with LIKE on email, phone, and display name', async () => {
    const queries = [];
    const pool = {
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        return [[{ id: 1, email: 'a@test.local', phone: '+661', name: 'Alice' }]];
      },
    };
    const repo = new CouponRepository(pool);
    const rows = await repo.searchCustomers('alice');
    assert.equal(rows.length, 1);
    assert.match(queries[0].sql, /role = 'CUSTOMER'/);
    assert.match(queries[0].sql, /email LIKE \?/);
    assert.match(queries[0].sql, /phone LIKE \?/);
    assert.match(queries[0].sql, /display_name LIKE \?/);
    assert.deepEqual(queries[0].params.slice(0, 3), ['%alice%', '%alice%', '%alice%']);
  });
});
