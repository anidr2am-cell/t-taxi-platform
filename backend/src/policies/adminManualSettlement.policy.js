const ADMIN_MANUAL_NAME_SIGN_AMOUNT = 100;

function money(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function calculateAdminManualSettlement({ payoutAmount, customerChargeAmount, paymentMethod }) {
  const payout = money(payoutAmount);
  const customerCharge = money(customerChargeAmount);
  if (paymentMethod !== 'PAY_DRIVER' || payout == null || customerCharge == null) {
    return { settlementAmount: 0, commissionExempt: true };
  }
  const settlementAmount = Math.max(0, customerCharge - payout);
  return { settlementAmount, commissionExempt: settlementAmount === 0 };
}

module.exports = { ADMIN_MANUAL_NAME_SIGN_AMOUNT, calculateAdminManualSettlement };
