import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../features/booking/pages/guest_booking_lookup_page.dart';
import '../features/booking/services/guest_booking_lookup_service.dart';
import '../features/booking/models/guest_booking_lookup_result.dart';
import '../features/admin_dispatch/widgets/admin_customer_change_request_card.dart';
import '../features/driver/pages/driver_notifications_page.dart';
import '../features/driver/services/driver_api_service.dart';

void main() => runApp(const VoucherQaApp());
String get number => Uri.base.queryParameters['case'] == 'missing'
    ? 'TX209901010219'
    : Uri.base.queryParameters['case'] == 'unassigned'
    ? 'TX209901010220'
    : 'TX209901010218';
Future<Map<String, dynamic>> load(String path) async {
  final response = await http.get(Uri.parse('${AppConfig.apiBaseUrl}$path'));
  return Map<String, dynamic>.from(jsonDecode(response.body)['data'] as Map);
}

class QaLookup extends GuestBookingLookupService {
  @override
  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
    String? name,
  }) async {
    if (name != null)
      return super.lookup(
        bookingNumber: bookingNumber,
        phone: phone,
        name: name,
      );
    final data = await load('/qa/voucher?bookingNumber=$bookingNumber');
    final r = GuestBookingLookupResult.fromJson(
      data,
    ).copyWith(customerPhone: phone);
    await persist(r);
    return r;
  }
}

class QaDriver extends DriverApiService {
  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) =>
      load('/qa/inbox');
}

class VoucherQaApp extends StatelessWidget {
  const VoucherQaApp({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = Uri.base.queryParameters['lang'] ?? 'ko';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: Locale(lang),
      supportedLocales: AppLocalizations.customerSupportedLanguages
          .map(Locale.new)
          .toList(),
      localizationsDelegates: [
        AppLocalizationsDelegate(lang),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        appBar: AppBar(title: const Text('QA ONLY · Voucher edit')),
        body: const QaBody(),
      ),
    );
  }
}

class QaBody extends StatefulWidget {
  const QaBody({super.key});
  @override
  State<QaBody> createState() => _QaBodyState();
}

class _QaBodyState extends State<QaBody> {
  late final future = load(
    Uri.base.queryParameters['view'] == 'admin'
        ? '/qa/admin-detail?bookingNumber=$number'
        : '/qa/voucher?bookingNumber=$number',
  );
  @override
  Widget build(BuildContext context) {
    if (Uri.base.queryParameters['view'] == 'driver')
      return DriverNotificationsPage(api: QaDriver(), showAppBar: false);
    if (Uri.base.queryParameters['view'] == 'lookup')
      return GuestBookingLookupPage(
        lookupService: QaLookup(),
        enableCustomerTools: false,
      );
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, s) {
        if (s.hasError) return const Text('QA load failed');
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (Uri.base.queryParameters['view'] == 'admin')
          return ListView(
            children: [
              const Text(
                'QA ONLY · Request is not applied to itinerary automatically',
              ),
              Text(number),
              if (s.data!['customerChangeRequest'] is Map)
                AdminCustomerChangeRequestCard(
                  request: Map<String, dynamic>.from(
                    s.data!['customerChangeRequest'] as Map,
                  ),
                )
              else
                const Text('No customer change request yet'),
            ],
          );
        final result = GuestBookingLookupResult.fromJson(
          s.data!,
        ).copyWith(customerPhone: s.data!['qaPhone'] as String?);
        return GuestBookingLookupPage(
          initialResult: result,
          lookupService: QaLookup(),
          enableCustomerTools: false,
        );
      },
    );
  }
}
