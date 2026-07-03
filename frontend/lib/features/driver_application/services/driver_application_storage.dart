import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_application_models.dart';

class DriverApplicationSavedStatus {
  const DriverApplicationSavedStatus({
    required this.applicationNumber,
    required this.statusToken,
    required this.submittedAt,
  });

  final String applicationNumber;
  final String statusToken;
  final String submittedAt;
}

class DriverApplicationStorage {
  const DriverApplicationStorage();

  static const _numberKey = 'driver_application_number';
  static const _tokenKey = 'driver_application_status_token';
  static const _submittedAtKey = 'driver_application_submitted_at';

  Future<DriverApplicationSavedStatus?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final number = prefs.getString(_numberKey);
    final token = prefs.getString(_tokenKey);
    if (number == null || number.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return DriverApplicationSavedStatus(
      applicationNumber: number,
      statusToken: token,
      submittedAt: prefs.getString(_submittedAtKey) ?? '',
    );
  }

  Future<void> save(DriverApplicationReceipt receipt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_numberKey, receipt.applicationNumber);
    await prefs.setString(_tokenKey, receipt.statusToken);
    await prefs.setString(_submittedAtKey, receipt.submittedAt);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_numberKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_submittedAtKey);
  }
}
