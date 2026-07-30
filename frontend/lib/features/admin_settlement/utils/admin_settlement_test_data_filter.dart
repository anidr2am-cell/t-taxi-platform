const adminSettlementTestDataAmountThb = 100;

bool isAdminSettlementTestDataItem(Map<String, dynamic> item) {
  final currency = (item['currency'] as String?)?.trim().toUpperCase();
  if (currency != 'THB') return false;

  final amount = item['commissionAmount'];
  final num? parsed = switch (amount) {
    num value => value,
    String value => num.tryParse(value),
    _ => null,
  };
  if (parsed == null) return false;

  return parsed == adminSettlementTestDataAmountThb;
}

List<dynamic> filterAdminSettlementItems(
  List<dynamic> items, {
  required bool includeTestData,
}) {
  if (includeTestData) return items;
  return items
      .where(
        (item) =>
            !isAdminSettlementTestDataItem(Map<String, dynamic>.from(item as Map)),
      )
      .toList(growable: false);
}
