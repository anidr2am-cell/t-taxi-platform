const test = require('node:test');
const assert = require('node:assert/strict');

const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  normalizeCustomerPayment,
  operationalPaymentMethod,
  customerPaymentFromMetadata,
} = require('../src/utils/customerPayment');

function validBooking(payment) {
  return {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SEDAN',
    scheduledPickupAt: new Date(Date.now() + 86400000).toISOString(),
    origin: { address: 'BKK' },
    destination: { address: 'Pattaya' },
    passengers: { adults: 1 },
    customer: { name: 'Tester', phone: '0800000000' },
    payment,
  };
}

test('booking payment defaults to pay driver', () => {
  const { error, value } = createBookingSchema.validate(validBooking());
  assert.equal(error, undefined);
  assert.deepEqual(value.payment, { method: 'PAY_DRIVER' });
  assert.equal(operationalPaymentMethod(value.payment), 'PAY_DRIVER');
});
test('bank transfer requires KRW or THB and uses online settlement path', () => {
  const missing = createBookingSchema.validate(validBooking({ method: 'BANK_TRANSFER' }));
  assert.ok(missing.error);
  const { error, value } = createBookingSchema.validate(validBooking({
    method: 'BANK_TRANSFER', transferCurrency: 'KRW',
  }));
  assert.equal(error, undefined);
  assert.equal(operationalPaymentMethod(normalizeCustomerPayment(value.payment)), 'ONLINE');
});

test('customer-facing method is recovered from booking metadata', () => {
  assert.deepEqual(customerPaymentFromMetadata(JSON.stringify({
    customerPayment: { method: 'BANK_TRANSFER', transferCurrency: 'THB' },
  }), 'ONLINE'), { method: 'BANK_TRANSFER', transferCurrency: 'THB' });
});
