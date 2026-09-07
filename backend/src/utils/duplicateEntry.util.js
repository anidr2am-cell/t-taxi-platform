function duplicateEntryText(err) {
  return `${err?.message || ''} ${err?.sqlMessage || ''}`.toLowerCase();
}

function isDuplicateEntryError(err) {
  return err?.code === 'ER_DUP_ENTRY';
}

function isDuplicatePhoneEntry(err) {
  if (!isDuplicateEntryError(err)) {
    return false;
  }
  const text = duplicateEntryText(err);
  return text.includes('uk_users_phone')
    || text.includes('idx_users_phone')
    || text.includes('.phone');
}

function isDuplicateEmailEntry(err) {
  if (!isDuplicateEntryError(err)) {
    return false;
  }
  const text = duplicateEntryText(err);
  return text.includes('uk_users_email')
    || text.includes('email_active');
}

module.exports = {
  isDuplicateEntryError,
  isDuplicatePhoneEntry,
  isDuplicateEmailEntry,
};
