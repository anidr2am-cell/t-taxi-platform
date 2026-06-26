const CHARGE_POLICY_TYPES = require('../constants/chargePolicyTypes');
const CHARGE_TYPES = require('../constants/chargeTypes');

const POLICY_TO_CHARGE_TYPE = {
  [CHARGE_POLICY_TYPES.NAME_SIGN]: CHARGE_TYPES.NAME_SIGN,
  [CHARGE_POLICY_TYPES.WAITING]: CHARGE_TYPES.WAITING_CHARGE,
  [CHARGE_POLICY_TYPES.PARKING]: CHARGE_TYPES.OTHER,
  [CHARGE_POLICY_TYPES.TOLL]: CHARGE_TYPES.TOLL_GATE,
  [CHARGE_POLICY_TYPES.HOLIDAY]: CHARGE_TYPES.HOLIDAY_SURCHARGE,
  [CHARGE_POLICY_TYPES.NIGHT]: CHARGE_TYPES.NIGHT_SURCHARGE,
  [CHARGE_POLICY_TYPES.AIRPORT]: CHARGE_TYPES.AIRPORT_SURCHARGE,
};

function mapPolicyTypeToChargeType(policyType) {
  return POLICY_TO_CHARGE_TYPE[policyType] || CHARGE_TYPES.OTHER;
}

function isEffectiveAt(record, at) {
  if (!at) {
    return true;
  }

  const when = at instanceof Date ? at : new Date(at);
  if (Number.isNaN(when.getTime())) {
    return true;
  }

  const effectiveFrom = record.effectiveFrom ?? record.effective_from;
  const effectiveTo = record.effectiveTo ?? record.effective_to;

  if (effectiveFrom) {
    const from = new Date(effectiveFrom);
    if (when < from) {
      return false;
    }
  }

  if (effectiveTo) {
    const to = new Date(effectiveTo);
    if (when > to) {
      return false;
    }
  }

  return true;
}

function periodBounds(effectiveFrom, effectiveTo) {
  const start = effectiveFrom ? new Date(effectiveFrom) : new Date('1970-01-01T00:00:00.000Z');
  const end = effectiveTo ? new Date(effectiveTo) : new Date('9999-12-31T23:59:59.999Z');
  return { start, end };
}

function periodsOverlap(periodA, periodB) {
  const a = periodBounds(periodA.effectiveFrom, periodA.effectiveTo);
  const b = periodBounds(periodB.effectiveFrom, periodB.effectiveTo);
  return a.start <= b.end && b.start <= a.end;
}

function roundMoney(value) {
  return Math.round(value * 100) / 100;
}

module.exports = {
  mapPolicyTypeToChargeType,
  isEffectiveAt,
  periodsOverlap,
  roundMoney,
};
