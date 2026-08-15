const DEFAULT_LOCK_TIMEOUT_SECONDS = 10;

async function acquireNamedLock(conn, lockName, timeoutSeconds = DEFAULT_LOCK_TIMEOUT_SECONDS) {
  const [rows] = await conn.query(
    'SELECT GET_LOCK(?, ?) AS acquired',
    [lockName, timeoutSeconds],
  );
  const acquired = rows?.[0]?.acquired;
  if (acquired === 1 || acquired === '1') {
    return true;
  }
  if (acquired === 0 || acquired === '0') {
    return false;
  }
  return null;
}

async function releaseNamedLock(conn, lockName) {
  const [rows] = await conn.query(
    'SELECT RELEASE_LOCK(?) AS released',
    [lockName],
  );
  const released = rows?.[0]?.released;
  return released === 1 || released === '1';
}

function contactDispatchLockName(bookingId) {
  return `tride:contact-dispatch:${bookingId}`;
}

module.exports = {
  DEFAULT_LOCK_TIMEOUT_SECONDS,
  acquireNamedLock,
  releaseNamedLock,
  contactDispatchLockName,
};
