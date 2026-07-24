process.env.NODE_ENV = "test";
process.env.DB_USER = process.env.DB_USER || "test";
process.env.DB_NAME = process.env.DB_NAME || "ttaxi_test";
process.env.JWT_ACCESS_SECRET =
  process.env.JWT_ACCESS_SECRET || "test-access-secret-value";
process.env.JWT_REFRESH_SECRET =
  process.env.JWT_REFRESH_SECRET || "test-refresh-secret-value";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const ChatService = require("../src/services/chat.service");
const ERROR_CODES = require("../src/constants/errorCodes");
const ROLES = require("../src/constants/roles");

const service = new ChatService(
  null,
  null,
  null,
  null,
  null,
  null,
  null,
);

function expectPeerBlocked(fn) {
  assert.throws(fn, (err) => {
    assert.equal(err.statusCode, 410);
    assert.equal(err.errorCode, ERROR_CODES.CHAT_NOT_ACCESSIBLE);
    return true;
  });
}

test("PR72 QA: driver role blocked before peer chat access", () => {
  expectPeerBlocked(() =>
    service.assertBookingPeerChatDisabled({ id: 44, role: ROLES.DRIVER }, null),
  );
});

test("PR72 QA: customer role blocked before peer chat access", () => {
  expectPeerBlocked(() =>
    service.assertBookingPeerChatDisabled({ id: 8, role: ROLES.CUSTOMER }, null),
  );
});

test("PR72 QA: guest token blocked before peer chat access", () => {
  expectPeerBlocked(() =>
    service.assertBookingPeerChatDisabled(null, "guest-token"),
  );
});

test("PR72 QA: admin role is not blocked by peer chat guard", () => {
  assert.doesNotThrow(() =>
    service.assertBookingPeerChatDisabled({ id: 1, role: ROLES.ADMIN }, null),
  );
});

test("PR72 QA: super admin role is not blocked by peer chat guard", () => {
  assert.doesNotThrow(() =>
    service.assertBookingPeerChatDisabled(
      { id: 1, role: ROLES.SUPER_ADMIN },
      null,
    ),
  );
});
