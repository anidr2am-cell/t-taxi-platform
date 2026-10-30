// Administrator copy-card projection only. Never updates bookings or settlements.
const COMPANY_COMMISSION_THB = 200;
function money(value) {
  if (value == null || !['number', 'string'].includes(typeof value) || String(value).trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.round(parsed * 100) / 100 : null;
}
function buildAdminDriverFinancialSummary(row, chargeItems = []) {
  let metadata = {};
  try { metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {}); } catch (_) {}
  const method = String(metadata?.customerPayment?.method ?? row.payment_method ?? '').trim().toUpperCase();
  const collectionMode = ['PAY_DRIVER','PAY_DRIVER_AT_DESTINATION'].includes(method) ? 'DRIVER_COLLECTS'
    : ['ADMIN_COLLECTED','ONLINE','BANK_TRANSFER','CARD','CREDIT_CARD'].includes(method) ? 'ADMIN_PAYS' : 'NEEDS_CONFIRMATION';
  const manual = row.booking_source === 'ADMIN_MANUAL';
  const total = money(row.total_amount);
  const signItems = chargeItems.filter(i => i.charge_type === 'NAME_SIGN' || i.chargeType === 'NAME_SIGN');
  const sign = signItems.every(i => money(i.amount) != null)
    ? money(signItems.reduce((sum,i) => sum + money(i.amount),0)) : null;
  const registeredPayout = money(metadata?.adminManualPricing?.payoutAmount);
  const recordedCommission = money(row.commission_amount);
  const finalized = ['SETTLEMENT_PENDING','COMPLETED'].includes(row.status);
  // A sign is an airport advance reimbursed to the driver, not a company deduction.
  const expectedReceipt = total != null && total >= COMPANY_COMMISSION_THB ? money(total - COMPANY_COMMISSION_THB) : null;
  const payoutConflict = manual && (registeredPayout == null || expectedReceipt == null || Math.abs(registeredPayout-expectedReceipt) > 0.009);
  // Never silently replace a different historical commission or waived settlement.
  // ADMIN_MANUAL + commission_exempt means no separate remittance, not zero company commission.
  const commissionConflict = !manual && ((recordedCommission != null && recordedCommission !== COMPANY_COMMISSION_THB)
    || [1,true,'1'].includes(row.commission_exempt) || (finalized && recordedCommission == null));
  const valid = row.currency === 'THB' && expectedReceipt != null && sign != null && sign <= expectedReceipt
    && !payoutConflict && !commissionConflict;
  const receipt = valid ? (manual ? registeredPayout : expectedReceipt) : null;
  const operatingIncome = receipt != null ? money(receipt - sign) : null;
  return {
    collectionMode, paymentMethod: method || null, paymentStatus: row.payment_status ?? null,
    currency: row.currency ?? null, customerTotalAmount: total,
    commissionAmount: row.currency === 'THB' ? COMPANY_COMMISSION_THB : null, recordedCommissionAmount: recordedCommission,
    nameSignAmount: sign, nameSignAdvanceAmount: sign, nameSignReimbursementAmount: sign,
    companyDeductionAmount: valid ? COMPANY_COMMISSION_THB : null,
    // Retain the former admin-only field as a receipt alias; new clients use explicit names.
    driverNetAmount: receipt, driverReceiptAmount: receipt, driverOperatingIncomeAmount: operatingIncome,
    registeredPayoutAmount: manual ? registeredPayout : null,
    collectFromCustomerAmount: collectionMode === 'ADMIN_PAYS' || row.payment_status === 'PAID' ? 0
      : collectionMode === 'DRIVER_COLLECTS' && row.payment_status === 'UNPAID' ? total : null,
    adminPayoutAmount: collectionMode === 'ADMIN_PAYS' ? receipt : null,
    basis: manual ? 'REGISTERED_PAYOUT' : recordedCommission == null ? 'CURRENT_TRIP_RULE_ESTIMATE' : 'RECORDED',
    needsConfirmation: !valid || collectionMode === 'NEEDS_CONFIRMATION' || !['PAID','UNPAID'].includes(row.payment_status),
    confirmationReason: payoutConflict ? 'REGISTERED_PAYOUT_DIFFERS_FROM_200_COMMISSION'
      : commissionConflict ? 'RECORDED_COMMISSION_REQUIRES_REVIEW' : !valid ? 'INCOMPLETE_OR_INCONSISTENT_AMOUNTS' : null,
  };
}
module.exports = { buildAdminDriverFinancialSummary, COMPANY_COMMISSION_THB };
