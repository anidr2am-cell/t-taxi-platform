import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_profile_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';

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

    expect(find.text('4.5 평균 / คะแนนเฉลี่ย'), findsOneWidget);
    expect(find.text('12 개 리뷰 / รีวิว'), findsOneWidget);
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

    expect(find.text('아직 평점이 없습니다\n(ยังไม่มีคะแนน)'), findsOneWidget);
    expect(find.text('0 개 리뷰 / รีวิว'), findsOneWidget);
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

    expect(find.text('오프라인\n(ออฟไลน์)'), findsOneWidget);
    await tester.tap(find.text('온라인 전환 / พร้อมรับงาน'));
    await tester.pumpAndSettle();

    expect(api.onlineCalls, 1);
    expect(find.text('온라인\n(พร้อมรับงาน)'), findsOneWidget);
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

    await tester.tap(find.text('오프라인 전환 / ออฟไลน์'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계속 시도 / ลองต่อ'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cannot go offline while an active trip is assigned'),
      findsOneWidget,
    );
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

  @override
  Future<Map<String, dynamic>> getRatingSummary() async {
    if (ratingError != null) throw ratingError!;
    return ratingSummary ?? {'averageRating': null, 'reviewCount': 0};
  }

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
