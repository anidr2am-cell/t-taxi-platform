const test = require('node:test');
const assert = require('node:assert/strict');

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const {
  CONTACT_DISPATCH_STATE,
  CONTACT_DISPATCH_MODE,
  deriveContactDispatch,
  isContactDispatchRetryable,
  canVerifyContact,
} = require('../src/policies/adminContactDispatch.policy');

const cases = [
  {
    name: 'gate=false immediate OPEN has no markers or contact flow',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: {},
    },
    state: CONTACT_DISPATCH_STATE.NOT_APPLICABLE,
    retryable: false,
    mode: CONTACT_DISPATCH_MODE.STANDARD,
  },
  {
    name: 'PENDING is waiting contact',
    input: {
      contactStatus: CONTACT_STATUS.PENDING,
      status: BOOKING_STATUS.OPEN,
      metadata: {},
      contactRequestedAt: null,
    },
    state: CONTACT_DISPATCH_STATE.WAITING_CONTACT,
    retryable: false,
  },
  {
    name: 'CONFIRM_REQUESTED is waiting contact',
    input: {
      contactStatus: CONTACT_STATUS.CONFIRM_REQUESTED,
      status: BOOKING_STATUS.OPEN,
      metadata: {},
      contactRequestedAt: '2026-09-26 01:00:00',
    },
    state: CONTACT_DISPATCH_STATE.WAITING_CONTACT,
    retryable: false,
    verify: true,
  },
  {
    name: 'VERIFIED contact flow without completed is dispatch pending',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: {},
      contactRequestedAt: '2026-09-26 01:00:00',
    },
    state: CONTACT_DISPATCH_STATE.DISPATCH_PENDING,
    retryable: true,
  },
  {
    name: 'connection row alone is enough contact-flow evidence',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: {},
      hasConnectionRow: true,
    },
    state: CONTACT_DISPATCH_STATE.DISPATCH_PENDING,
    retryable: true,
  },
  {
    name: 'completed only is delivery retry needed',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: { contactDispatchCompleted: true },
    },
    state: CONTACT_DISPATCH_STATE.DELIVERY_RETRY_NEEDED,
    retryable: true,
  },
  {
    name: 'delivered is delivery attempted',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: {
        contactDispatchCompleted: true,
        contactDispatchDelivered: true,
      },
    },
    state: CONTACT_DISPATCH_STATE.DELIVERY_ATTEMPTED,
    retryable: false,
  },
  {
    name: 'non-open with dispatch record is NOT_OPEN',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      metadata: { contactDispatchCompleted: true },
    },
    state: CONTACT_DISPATCH_STATE.NOT_OPEN,
    retryable: false,
  },
  {
    name: 'non-open CONFIRM_REQUESTED contact flow is NOT_OPEN and cannot verify',
    input: {
      contactStatus: CONTACT_STATUS.CONFIRM_REQUESTED,
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      metadata: {},
      contactRequestedAt: '2026-09-26 01:00:00',
    },
    state: CONTACT_DISPATCH_STATE.NOT_OPEN,
    retryable: false,
    verify: false,
  },
  {
    name: 'non-open immediate booking without contact flow is NOT_APPLICABLE',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      metadata: {},
    },
    state: CONTACT_DISPATCH_STATE.NOT_APPLICABLE,
    retryable: false,
    verify: false,
  },
  {
    name: 'urgent mode',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: { contactDispatchCompleted: true },
      is_urgent_request: 1,
    },
    state: CONTACT_DISPATCH_STATE.DELIVERY_RETRY_NEEDED,
    retryable: true,
    mode: CONTACT_DISPATCH_MODE.URGENT,
  },
  {
    name: 'current gate value is not required for leftover retry',
    input: {
      contactStatus: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: { contactDispatchCompleted: true },
      contactConnectionRequired: false,
    },
    state: CONTACT_DISPATCH_STATE.DELIVERY_RETRY_NEEDED,
    retryable: true,
  },
];

for (const fixture of cases) {
  test(`deriveContactDispatch: ${fixture.name}`, () => {
    const derived = deriveContactDispatch(fixture.input);
    assert.equal(derived.state, fixture.state);
    assert.equal(derived.retryable, fixture.retryable);
    assert.equal(isContactDispatchRetryable(fixture.input), fixture.retryable);
    if (fixture.mode) {
      assert.equal(derived.mode, fixture.mode);
    }
    assert.equal(canVerifyContact(fixture.input), fixture.verify === true);
  });
}
