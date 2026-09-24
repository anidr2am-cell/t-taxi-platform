const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  isDriverRegistrationVehicleType,
  DRIVER_REGISTRATION_EXCLUDED_CODES,
} = require('../src/utils/driverRegistrationVehicleTypes');

test('driver registration excludes VIP_VAN only', () => {
  assert.deepEqual(DRIVER_REGISTRATION_EXCLUDED_CODES, ['VIP_VAN']);
  assert.equal(isDriverRegistrationVehicleType('VAN'), true);
  assert.equal(isDriverRegistrationVehicleType('VIP_VAN'), false);
  assert.equal(isDriverRegistrationVehicleType('vip_van'), false);
});
