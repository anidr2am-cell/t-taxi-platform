process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const MileageService = require('../src/services/mileage.service');
const { computeAccrualAmount, ACCRUAL_RATE } = require('../src/services/mileage.service');
const { MILEAGE_TYPES } = require('../src/repositories/mileage.repository');
const AuthService = require('../src/services/auth.service');
const TokenService = require('../src/services/token.service');
const RevokedRefreshTokenStore = require('../src/services/revokedRefreshToken.store');
const SOCIAL_PROVIDERS = require('../src/constants/socialProviders');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const BookingStatusService = require('../src/services/bookingStatus.service');

function createInMemoryMileageRepository() {
  const accounts = new Map();
  const transactions = new Map();
  const bookings = new Map();
  let nextTxnId = 1;

  const repo = {
    setBooking(bookingId, data) {
      bookings.set(bookingId, { id: bookingId, ...data });
    },
    getAccountBalance(userId) {
      return accounts.get(userId)?.balance ?? 0;
    },
    listTransactions() {
      return [...transactions.values()];
    },
    async findBookingForAccrual(_conn, bookingId) {
      return bookings.get(bookingId) || null;
    },
    async findTransactionByBookingIdAndType(_conn, bookingId, type) {
      return transactions.get(`${bookingId}:${type}`) || null;
    },
    async insertTransaction(_conn, data) {
      const key = `${data.bookingId}:${data.type}`;
      if (transactions.has(key)) {
        const err = new Error('Duplicate mileage transaction');
        err.code = 'ER_DUP_ENTRY';
        throw err;
      }
      const row = {
        id: nextTxnId,
        user_id: data.userId,
        booking_id: data.bookingId,
        type: data.type,
        amount: data.amount,
        balance_after: data.balanceAfter,
        created_at: new Date(),
      };
      nextTxnId += 1;
      transactions.set(key, row);
      return row.id;
    },
    async updateTransactionBalanceAfter(_conn, transactionId, balanceAfter) {
      for (const row of transactions.values()) {
        if (row.id === transactionId) {
          row.balance_after = balanceAfter;
        }
      }
    },
    async getAccountForUpdate(_conn, userId) {
      const account = accounts.get(userId);
      return account ? { ...account } : null;
    },
    async createAccount(_conn, userId, balance = 0) {
      accounts.set(userId, { user_id: userId, balance });
    },
    async updateAccountBalance(_conn, userId, balance) {
      accounts.set(userId, { user_id: userId, balance });
    },
    async getBalance(userId) {
      return accounts.get(userId)?.balance ?? 0;
    },
    async getTransactionHistory(userId, { page = 1, limit = 20 } = {}) {
      const items = [...transactions.values()]
        .filter((row) => row.user_id === userId)
        .sort((a, b) => b.id - a.id);
      const offset = (page - 1) * limit;
      return {
        items: items.slice(offset, offset + limit),
        page,
        limit,
        total: items.length,
      };
    },
  };

  return repo;
}

function createMileageServiceHarness() {
  const mileageRepository = createInMemoryMileageRepository();
  const pool = {
    async getConnection() {
      return createConn();
    },
  };

  function createConn() {
    return {
      async beginTransaction() {},
      async commit() {},
      async rollback() {},
      release() {},
    };
  }

  const service = new MileageService(pool, mileageRepository, {});
  return { service, mileageRepository, pool };
}

test('computeAccrualAmount uses floor and avoids floating-point drift', () => {
  assert.equal(computeAccrualAmount(1600), 80);
  assert.equal(computeAccrualAmount(1601), 80);
  assert.equal(computeAccrualAmount(1999), 99);
  assert.equal(computeAccrualAmount(0), 0);
  assert.equal(computeAccrualAmount('2500.00'), 125);
  assert.equal(ACCRUAL_RATE, 0.05);
});

test('accrueForBooking credits 5% of total_amount', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(101, {
    customer_user_id: 7,
    total_amount: '1600.00',
  });

  const result = await service.accrueForBooking(101);
  assert.equal(result.accrued, true);
  assert.equal(result.amount, 80);
  assert.equal(result.balanceAfter, 80);
  assert.equal(await service.getBalance(7), 80);

  const txns = mileageRepository.listTransactions();
  assert.equal(txns.length, 1);
  assert.equal(txns[0].type, MILEAGE_TYPES.ACCRUE);
  assert.equal(txns[0].amount, 80);
  assert.equal(txns[0].balance_after, 80);
});

test('accrueForBooking skips guest booking without customer_user_id', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(102, {
    customer_user_id: null,
    total_amount: '2000.00',
  });

  const result = await service.accrueForBooking(102);
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'GUEST_BOOKING');
  assert.equal(mileageRepository.listTransactions().length, 0);
});

test('duplicate accrueForBooking calls are idempotent', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(103, {
    customer_user_id: 9,
    total_amount: '3000.00',
  });

  const first = await service.accrueForBooking(103);
  const second = await service.accrueForBooking(103);

  assert.equal(first.accrued, true);
  assert.equal(first.amount, 150);
  assert.equal(second.skipped, true);
  assert.equal(second.idempotent, true);
  assert.equal(await service.getBalance(9), 150);
  assert.equal(mileageRepository.listTransactions().length, 1);
});

test('concurrent accrueForBooking calls still accrue once', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(104, {
    customer_user_id: 11,
    total_amount: '4000.00',
  });

  const results = await Promise.all(
    Array.from({ length: 12 }, () => service.accrueForBooking(104)),
  );

  const accruedCount = results.filter((item) => item.accrued).length;
  const skippedCount = results.filter((item) => item.skipped && item.idempotent).length;

  assert.equal(accruedCount, 1);
  assert.equal(skippedCount, 11);
  assert.equal(await service.getBalance(11), 200);
  assert.equal(mileageRepository.listTransactions().length, 1);
});

test('reverseForBooking restores balance after cancellation', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(105, {
    customer_user_id: 15,
    total_amount: '2200.00',
  });

  await service.accrueForBooking(105);
  assert.equal(await service.getBalance(15), 110);

  const reversed = await service.reverseForBooking(105);
  assert.equal(reversed.reversed, true);
  assert.equal(reversed.amount, -110);
  assert.equal(reversed.balanceAfter, 0);
  assert.equal(await service.getBalance(15), 0);

  const txns = mileageRepository.listTransactions();
  assert.equal(txns.length, 2);
  assert.equal(txns.find((row) => row.type === MILEAGE_TYPES.REVERSAL).amount, -110);
});

test('reverseForBooking is idempotent and skips when no accrue exists', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(106, {
    customer_user_id: 16,
    total_amount: '1000.00',
  });

  const missing = await service.reverseForBooking(106);
  assert.equal(missing.skipped, true);
  assert.equal(missing.reason, 'NO_ACCRUE');

  await service.accrueForBooking(106);
  const first = await service.reverseForBooking(106);
  const second = await service.reverseForBooking(106);

  assert.equal(first.reversed, true);
  assert.equal(second.skipped, true);
  assert.equal(second.idempotent, true);
  assert.equal(mileageRepository.listTransactions().length, 2);
});

test('reverseForBooking never drives balance below zero', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(107, {
    customer_user_id: 17,
    total_amount: '1000.00',
  });

  await service.accrueForBooking(107);
  await mileageRepository.updateAccountBalance(null, 17, 20);

  const reversed = await service.reverseForBooking(107);
  assert.equal(reversed.balanceAfter, 0);
  assert.equal(await service.getBalance(17), 0);
});

test('getTransactionHistory returns paginated ledger rows', async () => {
  const { service, mileageRepository } = createMileageServiceHarness();
  mileageRepository.setBooking(201, { customer_user_id: 21, total_amount: '1000.00' });
  mileageRepository.setBooking(202, { customer_user_id: 21, total_amount: '2000.00' });
  await service.accrueForBooking(201);
  await service.accrueForBooking(202);

  const page = await service.getTransactionHistory(21, { page: 1, limit: 1 });
  assert.equal(page.total, 2);
  assert.equal(page.items.length, 1);
});

test('auth getMe includes authProvider and linkedProviders from social accounts', async () => {
  const userRepository = {
    async findById(id) {
      return {
        id,
        email: 'linked@example.com',
        role: 'CUSTOMER',
        phone: null,
        locale: 'ko',
        is_active: 1,
      };
    },
  };
  const socialAccountRepository = {
    async findProvidersByUserId(userId) {
      assert.equal(userId, 88);
      return [SOCIAL_PROVIDERS.GOOGLE, SOCIAL_PROVIDERS.KAKAO];
    },
  };
  const tokenService = new TokenService(new RevokedRefreshTokenStore());
  const authService = new AuthService(userRepository, tokenService, socialAccountRepository);

  const me = await authService.getMe(88);
  assert.equal(me.authProvider, SOCIAL_PROVIDERS.GOOGLE);
  assert.deepEqual(me.linkedProviders, [SOCIAL_PROVIDERS.GOOGLE, SOCIAL_PROVIDERS.KAKAO]);
});

test('buildAuthResponse uses login provider as authProvider', async () => {
  const user = {
    id: 90,
    email: 'social@example.com',
    role: 'CUSTOMER',
    phone: null,
    locale: 'ko',
    is_active: 1,
  };
  const socialAccountRepository = {
    async findProvidersByUserId() {
      return [SOCIAL_PROVIDERS.GOOGLE, SOCIAL_PROVIDERS.LINE];
    },
  };
  const tokenService = new TokenService(new RevokedRefreshTokenStore());
  const authService = new AuthService({}, tokenService, socialAccountRepository);

  const response = await authService.buildAuthResponse(user, SOCIAL_PROVIDERS.LINE);
  assert.equal(response.user.authProvider, SOCIAL_PROVIDERS.LINE);
  assert.deepEqual(response.user.linkedProviders, [SOCIAL_PROVIDERS.GOOGLE, SOCIAL_PROVIDERS.LINE]);
  assert.ok(response.accessToken);
});

test('bookingStatusService triggers mileage accrue after SETTLEMENT_PENDING', async () => {
  const calls = [];
  const mileageService = {
    async accrueForBooking(bookingId) {
      calls.push(['accrue', bookingId]);
    },
    async reverseForBooking(bookingId) {
      calls.push(['reverse', bookingId]);
    },
  };
  const bookingStatusService = new BookingStatusService({}, {}, {}, {}, mileageService);

  await bookingStatusService.handlePostCommitMileageEffects({
    bookingId: 501,
    fromStatus: BOOKING_STATUS.PICKED_UP,
    toStatus: BOOKING_STATUS.SETTLEMENT_PENDING,
  });

  assert.deepEqual(calls, [['accrue', 501]]);
});

test('bookingStatusService triggers mileage reversal when cancelling accrued booking', async () => {
  const calls = [];
  const mileageService = {
    async accrueForBooking(bookingId) {
      calls.push(['accrue', bookingId]);
    },
    async reverseForBooking(bookingId) {
      calls.push(['reverse', bookingId]);
    },
  };
  const bookingStatusService = new BookingStatusService({}, {}, {}, {}, mileageService);

  await bookingStatusService.handlePostCommitMileageEffects({
    bookingId: 502,
    fromStatus: BOOKING_STATUS.SETTLEMENT_PENDING,
    toStatus: BOOKING_STATUS.CANCELLED,
  });

  assert.deepEqual(calls, [['reverse', 502]]);
});

test('bookingStatusService skips mileage reversal for pre-accrual cancellation', async () => {
  const calls = [];
  const mileageService = {
    async accrueForBooking(bookingId) {
      calls.push(['accrue', bookingId]);
    },
    async reverseForBooking(bookingId) {
      calls.push(['reverse', bookingId]);
    },
  };
  const bookingStatusService = new BookingStatusService({}, {}, {}, {}, mileageService);

  await bookingStatusService.handlePostCommitMileageEffects({
    bookingId: 503,
    fromStatus: BOOKING_STATUS.PICKED_UP,
    toStatus: BOOKING_STATUS.CANCELLED,
  });

  assert.deepEqual(calls, []);
});
