import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../features/booking/widgets/gate_arrival_action.dart';
import '../features/driver/widgets/driver_arrival_readiness_card.dart';
import '../features/driver/services/driver_api_service.dart';
import '../features/admin_dispatch/widgets/admin_gate_arrival_link.dart';
import '../features/booking/widgets/airport_meeting_guide_card.dart';
import '../config/app_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const GateArrivalQaApp());

class QaDriverApi extends DriverApiService {
  @override
  Future<String?> getSavedToken() async => 'qa-only';
  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async {
    final r = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/qa/inbox'));
    return Map<String, dynamic>.from(jsonDecode(r.body)['data'] as Map);
  }
}

class GateArrivalQaApp extends StatelessWidget {
  const GateArrivalQaApp({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = Uri.base.queryParameters['lang'] ?? 'ko';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: Locale(lang),
      supportedLocales: AppLocalizations.customerSupportedLanguages.map(
        Locale.new,
      ),
      localizationsDelegates: [
        AppLocalizationsDelegate(lang),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('QA ONLY · Gate 7')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '격리 QA · 실제 기사·고객 알림 없음 / QA ONLY · No live push or email',
              ),
              if (Uri.base.queryParameters['view'] == 'driver')
                DriverArrivalReadinessCard(api: QaDriverApi())
              else if (Uri.base.queryParameters['view'] == 'admin')
                const AdminGateArrivalLink(bookingNumber: 'TX209901010217')
              else
                const AirportMeetingGuideCard(
                  serviceTypeCode: 'AIRPORT_PICKUP',
                  originAirportCode: 'BKK',
                  nameSignRequested: false,
                  vehicleInfo: AirportMeetingVehicleInfo(
                    driverName: 'QA Driver',
                    vehiclePlateNumber: 'QA123',
                  ),
                  arrivalAction: GateArrivalAction(
                    bookingNumber: 'TX209901010217',
                    guestToken: 'qa-gate-arrival',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
