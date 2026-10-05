const CUSTOMER_PAYMENT_METHODS = Object.freeze({
  PAY_DRIVER: 'PAY_DRIVER',
  BANK_TRANSFER: 'BANK_TRANSFER',
  CARD: 'CARD',
});

const TRANSFER_CURRENCIES = Object.freeze({ KRW: 'KRW', THB: 'THB' });

function normalizeCustomerPayment(payment = {}) {
  const method = String(payment.method || CUSTOMER_PAYMENT_METHODS.PAY_DRIVER).trim().toUpperCase();
  const transferCurrency = method === CUSTOMER_PAYMENT_METHODS.BANK_TRANSFER
    ? String(payment.transferCurrency || '').trim().toUpperCase()
    : null;
  return { method, transferCurrency: transferCurrency || null };
}

function operationalPaymentMethod(customerPayment) {
  return customerPayment.method === CUSTOMER_PAYMENT_METHODS.PAY_DRIVER ? 'PAY_DRIVER' : 'ONLINE';
}

function customerPaymentFromMetadata(metadata, fallback = 'PAY_DRIVER') {
  let parsed = metadata;
  if (typeof parsed === 'string') {
    try { parsed = JSON.parse(parsed); } catch (_) { parsed = {}; }
  }
  const stored = parsed && typeof parsed === 'object' ? parsed.customerPayment : null;
  return normalizeCustomerPayment(stored || { method: fallback });
}

module.exports = {
  CUSTOMER_PAYMENT_METHODS,
  TRANSFER_CURRENCIES,
  normalizeCustomerPayment,
  operationalPaymentMethod,
  customerPaymentFromMetadata,
};
