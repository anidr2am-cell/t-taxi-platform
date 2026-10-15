const REJECT_COMMANDS = new Set(['CONN', 'EHLO', 'HELO', 'STARTTLS', 'AUTH', 'MAIL FROM', 'RCPT TO', 'DATA']);
function smtpFailureEvidence(err) {
  const command = String(err?.command || '').toUpperCase();
  const responseCode = Number(err?.responseCode);
  const code = /^[A-Z0-9_]{1,80}$/.test(String(err?.code || '')) ? err.code : 'EMAIL_SEND_ERROR';
  // Negative SMTP responses prove the message was not accepted. A connection
  // failure is definitive only before any SMTP exchange, never after DATA.
  const rejected = REJECT_COMMANDS.has(command) && responseCode >= 400 && responseCode <= 599;
  // Nodemailer can report CONN/ECONNECTION or CONN/ETIMEDOUT even after DATA.
  // Neither proves non-acceptance. Only DNS/refused connection is definitive.
  const connectionFailed = command === 'CONN' && ['ECONNREFUSED', 'EDNS'].includes(code);
  return { outcome: rejected || connectionFailed ? 'NOT_ACCEPTED' : 'UNKNOWN', errorCode: code,
    smtpCommand: REJECT_COMMANDS.has(command) ? command : null,
    smtpResponseCode: Number.isInteger(responseCode) && responseCode >= 100 && responseCode < 600 ? responseCode : null };
}
function canRecoverAttempt(attempt) {
  if (attempt?.outcome !== 'NOT_ACCEPTED') return false;
  return smtpFailureEvidence({ code: attempt.error_code, command: attempt.smtp_command,
    responseCode: attempt.smtp_response_code }).outcome === 'NOT_ACCEPTED';
}
module.exports = { smtpFailureEvidence, canRecoverAttempt };
