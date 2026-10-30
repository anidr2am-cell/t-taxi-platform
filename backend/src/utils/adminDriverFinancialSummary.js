const DriverJobService = require('../services/driverJob.service');
const { commissionAmountAtTripEnd } = require('../policies/tripCommission.policy');
const mapper = new DriverJobService(null); // Only the existing pure payment mapper is used; no repository calls.
function money(v) {
  if (v == null || (typeof v !== 'number' && typeof v !== 'string') || String(v).trim() === '') return null;
  const n = Number(v); return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
}
function buildAdminDriverFinancialSummary(row, chargeItems = []) {
  let metadata = {}; try { metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {}); } catch (_) {}
  const method = String(metadata?.customerPayment?.method ?? row.payment_method ?? '').trim().toUpperCase();
  const collectionMode = ['PAY_DRIVER','PAY_DRIVER_AT_DESTINATION'].includes(method) ? 'DRIVER_COLLECTS'
    : ['ADMIN_COLLECTED','ONLINE','BANK_TRANSFER','CARD','CREDIT_CARD'].includes(method) ? 'ADMIN_PAYS' : 'NEEDS_CONFIRMATION';
  const exempt = [1,true,'1'].includes(row.commission_exempt);
  const manual = row.booking_source === 'ADMIN_MANUAL';
  const total = money(row.total_amount);
  const signItems = chargeItems.filter(i => i.charge_type === 'NAME_SIGN' || i.chargeType === 'NAME_SIGN');
  const sign = signItems.every(i => money(i.amount) != null) ? Math.round(signItems.reduce((n,i)=>n+money(i.amount),0)*100)/100 : null;
  const recordedCommission = money(row.commission_amount);
  const finalized = ['SETTLEMENT_PENDING','COMPLETED'].includes(row.status);
  const estimated = !manual && !(recordedCommission > 0) && !exempt && !finalized;
  const commissionForMapper = exempt ? 0 : (!manual && !finalized ? commissionAmountAtTripEnd(row,false) : recordedCommission);
  const mapped = mapper.paymentSummary({...row,metadata,commission_amount:commissionForMapper,name_sign_amount:sign ?? 0});
  const net = money(manual ? metadata?.adminManualPricing?.payoutAmount : mapped.driverExpectedIncomeAmount);
  const deduction = total != null && net != null && net <= total ? Math.round((total-net)*100)/100 : null;
  // A manual call's settlement amount already includes the sign charge: do not deduct it twice.
  const commission = manual ? (deduction != null && sign != null && sign <= deduction ? Math.round((deduction-sign)*100)/100 : null) : commissionForMapper;
  const valid = total != null && sign != null && commission != null && net != null && deduction != null && Math.abs(total-commission-sign-net)<0.011;
  return {
    collectionMode, paymentMethod: method || null, paymentStatus: row.payment_status ?? null,
    currency: row.currency ?? null, customerTotalAmount: total,
    commissionAmount: valid ? commission : null, nameSignAmount: sign,
    companyDeductionAmount: valid ? deduction : null, driverNetAmount: valid ? net : null,
    collectFromCustomerAmount: collectionMode === 'ADMIN_PAYS' || row.payment_status === 'PAID' ? 0
      : collectionMode === 'DRIVER_COLLECTS' && row.payment_status === 'UNPAID' ? total : null,
    adminPayoutAmount: collectionMode === 'ADMIN_PAYS' && valid ? net : null,
    basis: manual ? 'REGISTERED_PAYOUT' : estimated ? 'CURRENT_TRIP_RULE_ESTIMATE' : 'RECORDED',
    needsConfirmation: !valid || !String(row.currency ?? '').trim() || collectionMode === 'NEEDS_CONFIRMATION' || !['PAID','UNPAID'].includes(row.payment_status),
  };
}
module.exports = { buildAdminDriverFinancialSummary };
