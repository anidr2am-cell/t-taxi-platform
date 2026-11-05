import '../features/notification/services/notification_device_registration_service.dart';
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

class QaPushRegistration extends NotificationDeviceRegistrationService {
  @override Future<NotificationDeviceRegistrationResult> enableAuthenticated({required Future<String?> Function() accessTokenLoader}) async {
    final result=await super.enableAuthenticated(accessTokenLoader:accessTokenLoader);
    debugPrint('QA_PUSH_STATUS: ${result.status.name} ${result.message ?? ""}');
    return result;
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
              if ((Uri.base.queryParameters['view'] == 'driver' || Uri.base.path.startsWith('/driver')))
                DriverArrivalReadinessCard(api: QaDriverApi(),registration:QaPushRegistration())
              else if (Uri.base.queryParameters['view'] == 'admin')
                const ResolvedAirportQaView(admin: true)
              else
                const ResolvedAirportQaView(admin: false),
            ],
          ),
        ),
      ),
    );
  }
}


/// Uses the real service response, including the production display condition.
class ResolvedAirportQaView extends StatefulWidget {
  const ResolvedAirportQaView({super.key, required this.admin});
  final bool admin;
  @override
  State<ResolvedAirportQaView> createState() => _ResolvedAirportQaViewState();
}
class _ResolvedAirportQaViewState extends State<ResolvedAirportQaView> {
  late final Future<Map<String,dynamic>> detail = http.get(
    Uri.parse('${AppConfig.apiBaseUrl}/qa/detail'),
  ).then((r) => Map<String,dynamic>.from(jsonDecode(r.body)['data'] as Map));
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String,dynamic>>(
    future: detail,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('QA detail failed');
      if (!snapshot.hasData) return const CircularProgressIndicator();
      final data = snapshot.data!;
      final airport = data['flight']?['airportIata'] as String?;
      final service = data['serviceType']?['code'] as String?;
      final nameSign = data['options']?['nameSign'] == true;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('QA manual booking · stored airport: NULL · resolved: $airport'),
        Text('Assignment unchanged: driver ${data['activeAssignment']?['driverId']}'),
        if (widget.admin) ...[
          if (service == 'AIRPORT_PICKUP' && airport == 'BKK' && !nameSign)
            AdminGateArrivalLink(bookingNumber: data['bookingNumber'] as String),
        ] else AirportMeetingGuideCard(
          serviceTypeCode: service ?? '', originAirportCode: airport,
          nameSignRequested: nameSign,
          vehicleInfo: const AirportMeetingVehicleInfo(driverName:'QA Driver',vehiclePlateNumber:'QA123'),
          arrivalAction: GateArrivalAction(bookingNumber:data['bookingNumber'] as String,guestToken:'qa-gate-arrival'),
        ),
      ]);
    },
  );
}
