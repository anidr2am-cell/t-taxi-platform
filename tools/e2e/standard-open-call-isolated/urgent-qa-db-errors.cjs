'use strict';

/** Safe DB error summary (no SQL text, credentials, or row data). */
function formatDbError(err) {
  if (!err) return { kind: 'db', code: null };
  const message = String(err.message || err);
  const missingTable = message.match(/Table '[^']+\.([^']+)' doesn't exist/i)?.[1]
    ?? message.match(/Table '([^']+)' doesn't exist/i)?.[1]
    ?? null;
  const unknownColumn = message.match(/Unknown column '([^']+)'/i)?.[1] ?? null;
  return {
    kind: 'db',
    errno: err.errno ?? null,
    code: err.code ?? null,
    missingTable,
    unknownColumn,
  };
}

function formatFatalDbError(err) {
  return `db_error:${JSON.stringify(formatDbError(err))}`;
}

function isQaPasswordMissing(err) {
  if (!err) return false;
  if (err.code === 'QA_PASSWORD_MISSING') return true;
  const message = String(err.message || '');
  return /Missing QA driver password/i.test(message)
    || /QA_DRIVER_PASSWORD_FILE is empty/i.test(message)
    || /QA_DRIVER_PASSWORD_FILE unreadable/i.test(message);
}

function isMysqlDbError(err) {
  if (!err || typeof err !== 'object') return false;
  if (err.db && typeof err.db === 'object') return true;
  if (Number.isInteger(err.errno)) return true;
  const code = String(err.code || '');
  if (code.startsWith('ER_')) return true;
  if (code === 'PROTOCOL_CONNECTION_LOST') return true;
  const message = String(err.message || '');
  return /Table .+ doesn.t exist/i.test(message)
    || /Unknown column /i.test(message);
}

function classifyFatalRunnerError(err, stage) {
  const st = stage || null;
  if (isQaPasswordMissing(err)) {
    return { kind: 'qa_password_missing', stage: st };
  }
  if (isMysqlDbError(err)) {
    return { ...formatDbError(err), kind: 'db_error', stage: st };
  }
  const message = String(err?.message || '');
  if (/connect_timeout|connect_error|websocket|socket/i.test(message)) {
    return { kind: 'socket', stage: st };
  }
  if (/fetch failed|TypeError: fetch|ECONNREFUSED|ENOTFOUND/i.test(message)) {
    return { kind: 'fetch', stage: st };
  }
  return { kind: 'runtime', stage: st };
}

/** Fatal string for runners: never include secrets, SQL, or raw Error.message. */
function formatFatalRunnerError(err, stage) {
  const info = classifyFatalRunnerError(err, stage);
  if (info.kind === 'db_error') {
    return `db_error:${JSON.stringify({
      kind: 'db',
      errno: info.errno ?? null,
      code: info.code ?? null,
      missingTable: info.missingTable ?? null,
      unknownColumn: info.unknownColumn ?? null,
      stage: info.stage,
    })}`;
  }
  return `${info.kind}:${JSON.stringify({ kind: info.kind, stage: info.stage })}`;
}

module.exports = {
  formatDbError,
  formatFatalDbError,
  isQaPasswordMissing,
  isMysqlDbError,
  classifyFatalRunnerError,
  formatFatalRunnerError,
};
