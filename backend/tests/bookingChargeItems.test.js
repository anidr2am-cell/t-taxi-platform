process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const BookingRepository = require('../src/repositories/booking.repository');
const CHARGE_TYPES = require('../src/constants/chargeTypes');

test('booking charge item insert preserves canonical charge types from pricing', async () => {
  const repository = new BookingRepository({});
  const inserts = [];
  const conn = {
    async query(sql, params) {
      inserts.push({ sql, params });
    },
  };

  for (const chargeType of [
    CHARGE_TYPES.VEHICLE_BASE,
    CHARGE_TYPES.AIRPORT_SURCHARGE,
    CHARGE_TYPES.NAME_SIGN,
    CHARGE_TYPES.NIGHT_SURCHARGE,
    CHARGE_TYPES.WAITING_CHARGE,
  ]) {
    await repository.insertChargeItem(conn, 10, {
      chargeType,
      description: chargeType,
      quantity: 1,
      unitPrice: 100,
      amount: 100,
      referenceType: chargeType === CHARGE_TYPES.VEHICLE_BASE ? 'VEHICLE_PRICE' : 'CHARGE_POLICY',
      referenceId: 1,
    }, null);
  }

  assert.deepEqual(
    inserts.map((insert) => insert.params[1]),
    [
      CHARGE_TYPES.VEHICLE_BASE,
      CHARGE_TYPES.AIRPORT_SURCHARGE,
      CHARGE_TYPES.NAME_SIGN,
      CHARGE_TYPES.NIGHT_SURCHARGE,
      CHARGE_TYPES.WAITING_CHARGE,
    ],
  );
});
