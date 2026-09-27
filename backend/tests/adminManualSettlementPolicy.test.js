const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ADMIN_MANUAL_NAME_SIGN_AMOUNT,
  calculateAdminManualSettlement,
} = require('../src/policies/adminManualSettlement.policy');

test('equal customer payment and driver payout needs no settlement', () => {
  assert.deepEqual(calculateAdminManualSettlement({
    payoutAmount: 1200,
    customerChargeAmount: 1200,
    paymentMethod: 'PAY_DRIVER',
  }), { settlementAmount: 0, commissionExempt: true });
});

test('driver-collected customer surplus becomes company settlement', () => {
  assert.deepEqual(calculateAdminManualSettlement({
    payoutAmount: 1500,
    customerChargeAmount: 1800,
    nameSignAmount: ADMIN_MANUAL_NAME_SIGN_AMOUNT,
    paymentMethod: 'PAY_DRIVER',
  }), { settlementAmount: 200, commissionExempt: false });
});

test('admin-collected booking never creates a driver settlement', () => {
  assert.deepEqual(calculateAdminManualSettlement({
    payoutAmount: 1500,
    customerChargeAmount: 1800,
    nameSignAmount: 100,
    paymentMethod: 'ADMIN_COLLECTED',
  }), { settlementAmount: 0, commissionExempt: true });
});
