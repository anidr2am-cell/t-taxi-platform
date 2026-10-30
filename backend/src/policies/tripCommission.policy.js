// Shared with trip completion: preserve the existing settlement rule exactly.
function commissionAmountAtTripEnd(booking, commissionExempt) {
  const stored = Number(booking.commission_amount);
  return commissionExempt ? 0 : (Number.isFinite(stored) && stored > 0 ? stored : 200);
}
module.exports = { commissionAmountAtTripEnd };
