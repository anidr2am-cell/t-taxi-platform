import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dashboard/models/admin_dashboard_metrics.dart';
import 'package:frontend/features/admin_dashboard/pages/admin_dashboard_page.dart';
import 'package:frontend/features/admin_dashboard/services/admin_dashboard_api_service.dart';

void main() {
  testWidgets('shows loading state', (tester) async {
    final completer = Completer<AdminDashboardMetrics>();
    await tester.pumpWidget(_wrap(AdminDashboardPage(api: _FakeDashboardApi(completer: completer))));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_metrics());
  });

  testWidgets('renders success metrics and zero values', (tester) async {
    await tester.pumpWidget(_wrap(AdminDashboardPage(api: _FakeDashboardApi(metrics: _metricsZero()))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Operations for 2026-06-29'), findsOneWidget);
    expect(find.text('Today bookings'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('0 THB'), findsWidgets);
  });

  testWidgets('shows error and retry state', (tester) async {
    final api = _FakeDashboardApi(error: const AdminDashboardApiException('Boom'));
    await tester.pumpWidget(_wrap(AdminDashboardPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Boom'), findsOneWidget);

    api.error = null;
    api.metrics = _metrics();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Today bookings'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('refresh action reloads metrics', (tester) async {
    final api = _FakeDashboardApi(metrics: _metrics());
    await tester.pumpWidget(_wrap(AdminDashboardPage(api: api)));
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('tapping operational cards navigates where practical', (tester) async {
    var dispatchOpened = 0;
    var settlementsOpened = 0;
    await tester.pumpWidget(_wrap(
      AdminDashboardPage(
        api: _FakeDashboardApi(metrics: _metrics()),
        onOpenDispatch: () => dispatchOpened += 1,
        onOpenSettlements: () => settlementsOpened += 1,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unassigned'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Pending settlements'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pending settlements'));
    await tester.pump();

    expect(dispatchOpened, 1);
    expect(settlementsOpened, 1);
  });

  testWidgets('token-required behavior is rendered as controlled error', (tester) async {
    await tester.pumpWidget(_wrap(
      AdminDashboardPage(
        api: _FakeDashboardApi(error: const AdminDashboardApiException('Please log in')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Please log in'), findsOneWidget);
  });

  testWidgets('dashboard has no horizontal overflow at 768px', (tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(768, 1024)),
        child: _wrap(AdminDashboardPage(api: _FakeDashboardApi(metrics: _metrics()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today bookings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

AdminDashboardMetrics _metrics() => const AdminDashboardMetrics(
      date: '2026-06-29',
      timezone: 'Asia/Bangkok',
      bookings: BookingMetrics(
        today: 5,
        pending: 1,
        unassigned: 2,
        assigned: 1,
        onRoute: 1,
        arrived: 1,
        completed: 1,
        cancelled: 0,
        noShow: 0,
      ),
      drivers: DriverMetrics(online: 3, activeJobs: 2),
      settlements: SettlementMetrics(pending: 4, overdue: 1),
      revenue: RevenueMetrics(currency: 'THB', todayBooked: 1500, todayCompleted: 900),
      updatedAt: '2026-06-29T05:00:00.000Z',
    );

AdminDashboardMetrics _metricsZero() => const AdminDashboardMetrics(
      date: '2026-06-29',
      timezone: 'Asia/Bangkok',
      bookings: BookingMetrics(
        today: 0,
        pending: 0,
        unassigned: 0,
        assigned: 0,
        onRoute: 0,
        arrived: 0,
        completed: 0,
        cancelled: 0,
        noShow: 0,
      ),
      drivers: DriverMetrics(online: 0, activeJobs: 0),
      settlements: SettlementMetrics(pending: 0, overdue: 0),
      revenue: RevenueMetrics(currency: 'THB', todayBooked: 0, todayCompleted: 0),
      updatedAt: '2026-06-29T05:00:00.000Z',
    );

class _FakeDashboardApi extends AdminDashboardApiService {
  _FakeDashboardApi({this.metrics, this.error, this.completer});

  AdminDashboardMetrics? metrics;
  Object? error;
  Completer<AdminDashboardMetrics>? completer;
  int calls = 0;

  @override
  Future<AdminDashboardMetrics> getMetrics() async {
    calls += 1;
    if (completer != null) return completer!.future;
    if (error != null) throw error!;
    return metrics ?? _metrics();
  }
}
