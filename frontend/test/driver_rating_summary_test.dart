import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_profile_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/widgets/driver_status_control.dart';

void main() {
  testWidgets('driver rating summary shows average and review count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverProfilePage(
          api: _FakeDriverApi(
            ratingSummary: {'averageRating': 4.5, 'reviewCount': 12},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('4.5 · 12'), findsOneWidget);
    expect(find.text('Great service'), findsNothing);
  });

  testWidgets('driver rating summary shows no-ratings state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverProfilePage(
          api: _FakeDriverApi(
            ratingSummary: {'averageRating': null, 'reviewCount': 0},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีคะแนน'), findsOneWidget);
    expect(find.textContaining('0'), findsWidgets);
  });

  testWidgets('driver rating summary shows error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverProfilePage(
          api: _FakeDriverApi(
            ratingError: const DriverApiException('Rating unavailable'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('평점을 불러올 수 없습니다\n(ไม่สามารถโหลดคะแนนได้)'),
      findsOneWidget,
    );
    expect(find.text('average'), findsNothing);
  });

  testWidgets('driver profile renders offline state and goes online', (
    tester,
  ) async {
    final api = _FakeDriverApi();
    await tester.pumpWidget(MaterialApp(home: DriverProfilePage(api: api)));
    await tester.pumpAndSettle();

    final onlineButton = find.descendant(
      of: find.byType(DriverStatusControl),
      matching: find.widgetWithIcon(FilledButton, Icons.play_circle_fill),
    );
    await tester.scrollUntilVisible(
      onlineButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(onlineButton, findsOneWidget);
    await tester.tap(onlineButton);
    await tester.pumpAndSettle();

    expect(api.onlineCalls, 1);
    expect(
      find.widgetWithIcon(OutlinedButton, Icons.power_settings_new),
      findsOneWidget,
    );
  });

  testWidgets('driver profile active-job offline conflict is shown', (
    tester,
  ) async {
    final api = _FakeDriverApi(
      initialStatus: const DriverStatus(
        driverId: 7,
        active: true,
        online: true,
        status: 'AVAILABLE',
        hasActiveJob: true,
      ),
      offlineError: const DriverApiException(
        'Cannot go offline while an active trip is assigned',
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DriverProfilePage(api: api)));
    await tester.pumpAndSettle();

    final offlineButton = find.descendant(
      of: find.byType(DriverStatusControl),
      matching: find.widgetWithIcon(OutlinedButton, Icons.power_settings_new),
    );
    await tester.scrollUntilVisible(
      offlineButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<OutlinedButton>(offlineButton);
    expect(button.onPressed, isNull);
    expect(api.offlineCalls, 0);
  });
}

class _FakeDriverApi extends DriverApiService {
  _FakeDriverApi({
    this.ratingSummary,
    this.ratingError,
    DriverStatus? initialStatus,
    this.offlineError,
  }) : _status =
           initialStatus ??
           const DriverStatus(
             driverId: 7,
             active: true,
             online: false,
             status: 'OFFLINE',
             hasActiveJob: false,
           );

  final Map<String, dynamic>? ratingSummary;
  final Object? ratingError;
  final Object? offlineError;
  DriverStatus _status;
  int onlineCalls = 0;
  int offlineCalls = 0;

  @override
  Future<Map<String, dynamic>> getRatingSummary() async {
    if (ratingError != null) throw ratingError!;
    return ratingSummary ?? {'averageRating': null, 'reviewCount': 0};
  }

  @override
  Future<Map<String, dynamic>> getProfile() async => {
    'name': 'Somchai',
    'phone': '+66812345678',
    'email': 'driver@example.com',
    'vehicle': {
      'typeCode': 'SUV',
      'typeName': 'SUV',
      'modelName': 'Camry',
      'plateNumber': 'ABC-1234',
      'color': 'White',
      'year': 2022,
    },
  };

  @override
  Future<DriverStatus> getStatus() async => _status;

  @override
  Future<DriverStatus> goOnline() async {
    onlineCalls += 1;
    _status = const DriverStatus(
      driverId: 7,
      active: true,
      online: true,
      status: 'AVAILABLE',
      hasActiveJob: false,
      lastSeenAt: '2026-06-30 09:00:00',
    );
    return _status;
  }

  @override
  Future<DriverStatus> goOffline() async {
    offlineCalls += 1;
    if (offlineError != null) throw offlineError!;
    _status = const DriverStatus(
      driverId: 7,
      active: true,
      online: false,
      status: 'OFFLINE',
      hasActiveJob: false,
      lastSeenAt: '2026-06-30 09:00:00',
    );
    return _status;
  }
}
