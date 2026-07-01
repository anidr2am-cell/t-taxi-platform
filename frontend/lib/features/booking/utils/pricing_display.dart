import '../../../l10n/app_localizations.dart';
import '../models/pricing_result.dart';

class PricingDisplay {
  PricingDisplay._();

  static String chargeItemLabel(AppLocalizations l10n, ChargeLineItem item) {
    if (item.chargeType == 'NAME_SIGN') {
      return l10n.t('pricing_name_sign_with_picket');
    }
    return item.description;
  }
}
