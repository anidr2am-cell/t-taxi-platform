class ChargeLineItem {
  final String chargeType;
  final String description;
  final num quantity;
  final num unitPrice;
  final num amount;

  const ChargeLineItem({
    required this.chargeType,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });

  factory ChargeLineItem.fromJson(Map<String, dynamic> json) {
    return ChargeLineItem(
      chargeType: json['chargeType'] as String? ?? '',
      description: json['description'] as String? ?? '',
      quantity: json['quantity'] as num? ?? 1,
      unitPrice: json['unitPrice'] as num? ?? 0,
      amount: json['amount'] as num? ?? 0,
    );
  }
}

class PricingResult {
  final String currency;
  final List<ChargeLineItem> chargeItems;
  final num totalAmount;

  const PricingResult({
    required this.currency,
    required this.chargeItems,
    required this.totalAmount,
  });

  factory PricingResult.fromJson(Map<String, dynamic> json) {
    final items = (json['chargeItems'] as List<dynamic>? ?? [])
        .map((e) => ChargeLineItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return PricingResult(
      currency: json['currency'] as String? ?? 'THB',
      chargeItems: items,
      totalAmount: json['totalAmount'] as num? ?? 0,
    );
  }

  num get basePrice {
    return chargeItems
        .where((i) => i.chargeType == 'VEHICLE_BASE')
        .fold<num>(0, (sum, i) => sum + i.amount);
  }

  List<ChargeLineItem> get additionalCharges {
    return chargeItems.where((i) => i.chargeType != 'VEHICLE_BASE').toList();
  }
}
