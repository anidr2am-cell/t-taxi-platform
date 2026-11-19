String _compact(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s()+.\-]'), '');

bool matchesDriverSearch(Map<String, dynamic> driver, String query) {
  final needle = _compact(query.trim());
  if (needle.isEmpty) return true;
  final primary = driver['primaryVehicle'];
  final phone = _compact(driver['phone']?.toString() ?? '');
  final values = <String>[
    driver['displayName']?.toString() ?? '',
    driver['driverId']?.toString() ?? '',
    phone,
    if (RegExp(r'^66[689][0-9]{8}$').hasMatch(phone))
      '0${phone.substring(2)}',
    if (RegExp(r'^0[689][0-9]{8}$').hasMatch(phone))
      '66${phone.substring(1)}',
    if (primary is Map) primary['plateNumber']?.toString() ?? '',
    if (primary is Map) primary['modelName']?.toString() ?? '',
    for (final plate in driver['vehiclePlateNumbers'] as List? ?? [])
      plate.toString(),
  ];
  return values.any((value) => _compact(value).contains(needle));
}
