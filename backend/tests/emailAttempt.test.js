const test = require('node:test');
const assert = require('node:assert/strict');
const { smtpFailureEvidence, canRecoverAttempt } = require('../src/policies/emailAttempt.policy');
const { EmailNotificationAdapter } = require('../src/services/notificationDelivery.adapters');
const { encrypt, decrypt } = require('../src/utils/tokenEncryption.util');
const NotificationService = require('../src/services/notification.service');
const base = { id: 1, booking_id: 1, type: 'BOOKING_CREATED', audience_role: 'CUSTOMER',
  recipient_type: 'GUEST_BOOKING', recipient_email: 'qa@example.invalid', booking_number: 'QA_TRACE',
  booking_metadata: { locale: 'ko' }, origin_address: 'ORIGINAL', booking_total_amount: 1000 };
for (const [name, err, expected] of [
  ['negative RCPT', { command: 'RCPT TO', responseCode: 550, code: 'EENVELOPE' }, 'NOT_ACCEPTED'],
  ['negative DATA', { command: 'DATA', responseCode: 451, code: 'EMESSAGE' }, 'NOT_ACCEPTED'],
  ['connect refused', { command: 'CONN', code: 'ECONNREFUSED' }, 'NOT_ACCEPTED'],
  ['ambiguous CONN timeout', { command: 'CONN', code: 'ETIMEDOUT' }, 'UNKNOWN'],
  ['ambiguous CONN close', { command: 'CONN', code: 'ECONNECTION' }, 'UNKNOWN'],
  ['DATA timeout', { command: 'DATA', code: 'ETIMEDOUT' }, 'UNKNOWN'],
  ['connection lost after DATA', { command: 'DATA', code: 'ECONNECTION' }, 'UNKNOWN'],
  ['unattributed 550', { responseCode: 550, code: 'EMESSAGE' }, 'UNKNOWN'],
  ['internal database error', { code: 'ER_LOCK_DEADLOCK' }, 'UNKNOWN'],
]) test(`SMTP evidence ${name}`, () => {
  const e = smtpFailureEvidence(err); assert.equal(e.outcome, expected);
  assert.equal(canRecoverAttempt({ outcome: e.outcome, error_code: e.errorCode, smtp_command: e.smtpCommand, smtp_response_code: e.smtpResponseCode }), expected === 'NOT_ACCEPTED');
});
test('outcome label alone is never enough to authorize recovery', () => {
  assert.equal(canRecoverAttempt({ outcome: 'NOT_ACCEPTED' }), false);
  assert.equal(canRecoverAttempt({ outcome: 'UNKNOWN', smtp_command: 'DATA', smtp_response_code: 550 }), false);
});
function adapter(sendMail) { return new EmailNotificationAdapter({ smtp: { host: 'smtp.invalid', fromEmail: 'qa@example.invalid' }, transport: { sendMail } }); }
test('SMTP snapshot saved encrypted before send, stable Message-ID and trace header persisted', async () => {
  let encrypted; let sent;
  const a = adapter(async (mail) => { assert(encrypted); sent = mail; return { response: '250 queued as <provider-123>' }; });
  const result = await a.send(base, { emailAttempt: { id: 1, messageId: '<logical-1@trider.taxi>', traceId: 'trace-1' }, saveEmailEnvelope: async (value) => { encrypted = value; } });
  assert(!encrypted.includes('ORIGINAL')); assert.deepEqual(JSON.parse(decrypt(encrypted)), sent);
  assert.equal(sent.messageId, '<logical-1@trider.taxi>'); assert.equal(sent.headers['X-TRider-Email-Trace'], 'trace-1');
  assert.equal(result.emailTrace.outcome, 'ACCEPTED'); assert.equal(result.emailTrace.providerMessageId, 'provider-123');
});
test('recovery preserves original recipient, subject and body despite later booking/locale changes', async () => {
  const original = { to: base.recipient_email, from: 'qa@example.invalid', subject: 'ORIGINAL SUBJECT', text: 'ORIGINAL BODY', html: '<p>ORIGINAL</p>' };
  let sent;
  await adapter(async (m) => { sent = m; }).send({ ...base, booking_metadata: { locale: 'th' }, origin_address: 'CHANGED' },
    { emailAttempt: { envelope: encrypt(JSON.stringify(original)), messageId: '<same@trider.taxi>', traceId: 'new-attempt' } });
  assert.equal(sent.to, original.to); assert.equal(sent.subject, original.subject); assert.equal(sent.html, original.html); assert.equal(sent.text, original.text);
});
test('recipient changes or snapshot storage failure cannot trigger an SMTP call', async () => {
  let calls = 0; const a = adapter(async () => { calls++; });
  const result = await a.send(base, { emailAttempt: { envelope: encrypt(JSON.stringify({ to: 'other@example.invalid' })) } });
  assert.equal(result.emailTrace.outcome, 'UNKNOWN');
  await a.send(base, { emailAttempt: { traceId: 'x' }, saveEmailEnvelope: async () => { throw Error('storage failed'); } });
  assert.equal(calls, 0);
});
test('tracked SMTP negative reply is recoverable but uncertain DATA timeout stays blocked', async () => {
  for (const command of ['RCPT TO', 'DATA']) {
    const r = await adapter(async () => { throw Object.assign(Error('private SMTP detail'), { code: 'EENVELOPE', command, ...(command === 'RCPT TO' ? { responseCode: 550 } : {}) }); }).send(base, { emailAttempt: { traceId: 'qa' } });
    assert.equal(r.emailTrace.outcome, command === 'RCPT TO' ? 'NOT_ACCEPTED' : 'UNKNOWN');
    assert(!JSON.stringify(r).includes('private SMTP detail')); assert.match(r.error, /^PERMANENT_EMAIL_/);
  }
});
test('administrator recovery only claims existing EMAIL, not IN_APP/FCM; denied claims never send', async () => {
  let sent = 0; let recorded = 0;
  const repo = { async findEmailDelivery() { return { id: 4, notification_id: 1 }; }, async findById() { return base; },
    async claimCustomerEmail(_n, _d, input) { assert.equal(input.expectedAttemptId, 9); return { allowed: false }; },
    async addEmailReview() { recorded++; return true; } };
  const service = new NotificationService({}, repo, {}, {}, {}, {}, { EMAIL: { async send() { sent++; } } });
  await assert.rejects(() => service.reviewEmailDelivery(4, { action: 'RETRY_APPROVED', expectedAttemptId: 9, reason: 'proof' }, { role: 'ADMIN', id: 2 }), { statusCode: 409 });
  await service.reviewEmailDelivery(4, { action: 'HANDLED_EXTERNALLY', reason: 'contacted' }, { role: 'ADMIN', id: 2 });
  await assert.rejects(() => service.reviewEmailDelivery(4, {}, { role: 'DRIVER', id: 3 }), { statusCode: 403 });
  assert.equal(sent, 0); assert.equal(recorded, 1);
});
test('admin route accepts only server evidence IDs, ignores client-supplied outcome/proof/actor', async () => {
  const request = require('supertest'); const jwt = require('jsonwebtoken'); const app = require('../src/app');
  const token = jwt.sign({ sub: 2, role: 'ADMIN', type: 'access' }, process.env.JWT_ACCESS_SECRET, { expiresIn: '1h' });
  const path = '/api/v1/admin/notifications/email-review/4';
  assert.equal((await request(app).post(path).send({})).status, 401);
  const container = require('../src/helpers/container');
  const previous = container.registry.get('notificationService');
  let input;
  container.register('notificationService', () => ({ async reviewEmailDelivery(_id, body, actor) { input = { body, actor }; return {}; } }));
  try {
    const response = await request(app).post(path).set('Authorization', `Bearer ${token}`).send({ action: 'RETRY_APPROVED', expectedAttemptId: 1, reason: 'proof', outcome: 'NOT_ACCEPTED', actorUserId: 1 });
    assert.equal(response.status, 200); assert.equal(input.body.outcome, undefined); assert.equal(input.body.actorUserId, undefined); assert.equal(input.actor.id, 2);
    assert.equal((await request(app).post(path).set('Authorization', `Bearer ${token}`).send({ action: 'RETRY_APPROVED', reason: 'proof' })).status, 400);
  } finally { container.registry.set('notificationService', previous); }
});
test('missing SMTP configuration cannot consume a recovery claim or replace its rejection evidence', async () => {
  let claimed = 0;
  const repo = { async findEmailDelivery() { return { id: 4, notification_id: 1 }; }, async findById() { return base; },
    async claimCustomerEmail() { claimed++; return { allowed: true }; } };
  const service = new NotificationService({}, repo, {}, {}, {}, {}, { EMAIL: { isConfigured: () => false } });
  await assert.rejects(() => service.reviewEmailDelivery(4, { action: 'RETRY_APPROVED' }, { role: 'ADMIN', id: 2 }), { statusCode: 409 });
  assert.equal(claimed, 0);
});
