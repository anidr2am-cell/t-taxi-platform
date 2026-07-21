import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_ux.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/pages/driver_account_page.dart';
import 'package:frontend/features/driver/pages/driver_today_page.dart';
import 'package:frontend/features/driver_settlement/pages/driver_settlement_list_page.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';
import 'package:frontend/features/driver/pages/driver_jobs_page.dart';
import 'package:frontend/features/driver/pages/driver_login_page.dart';
import 'package:frontend/features/driver/pages/driver_qr_scan_page.dart';
import 'package:frontend/features/driver/pages/driver_shell_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver/widgets/driver_status_control.dart';

void main() {
  group('DriverUx grouping', () {
    test('active jobs include assigned, arrived, and picked up', () {
      expect(DriverUx.groupForStatus('DRIVER_ASSIGNED'), DriverJobGroup.active);
      expect(DriverUx.groupForStatus('DRIVER_ARRIVED'), DriverJobGroup.active);
      expect(DriverUx.groupForStatus('PICKED_UP'), DriverJobGroup.active);
    });

    test('completed group includes terminal statuses', () {
      expect(DriverUx.groupForStatus('COMPLETED'), DriverJobGroup.completed);
      expect(DriverUx.groupForStatus('CANCELLED'), DriverJobGroup.completed);
      expect(DriverUx.groupForStatus('NO_SHOW'), DriverJobGroup.completed);
    });

    test('groupBookings sorts active before upcoming and completed', () {
      final items = [
        _booking(status: 'COMPLETED', time: '18:00'),
        _booking(
          status: 'DRIVER_ASSIGNED',
          time: '10:00',
          number: 'TX202607010002',
        ),
        _booking(status: 'CONFIRMED', time: '12:00', number: 'TX202607010003'),
        _booking(status: 'PICKED_UP', time: '09:00', number: 'TX202607010004'),
      ];
      final grouped = DriverUx.groupBookings(items);
      expect(grouped[DriverJobGroup.active]!.length, 2);
      expect(grouped[DriverJobGroup.active]!.first.status, 'PICKED_UP');
      expect(grouped[DriverJobGroup.upcoming]!.length, 1);
      expect(grouped[DriverJobGroup.completed]!.length, 1);
    });

    test('canContactCustomer requires active booking status', () {
      expect(DriverUx.canContactCustomer('DRIVER_ASSIGNED'), true);
      expect(DriverUx.canContactCustomer('PICKED_UP'), true);
      expect(DriverUx.canContactCustomer('COMPLETED'), false);
      expect(DriverUx.canContactCustomer('CONFIRMED'), false);
    });
    test('selectCurrentTrip prefers picked up over assigned', () {
      final items = [
        _booking(status: 'DRIVER_ASSIGNED', time: '08:00'),
        _booking(status: 'PICKED_UP', time: '09:00', number: 'TX202607010004'),
      ];
      final current = DriverUx.selectCurrentTrip(items);
      expect(current?.status, 'PICKED_UP');
    });

    test('selectCurrentTrip uses nearest upcoming when no active trip', () {
      final items = [
        _booking(status: 'CONFIRMED', time: '12:00', number: 'TX202607010003'),
        _booking(status: 'PENDING', time: '10:00', number: 'TX202607010002'),
      ];
      final current = DriverUx.selectCurrentTrip(items);
      expect(current?.bookingNumber, 'TX202607010002');
    });

    test('remainingTodayTrips excludes current trip', () {
      final current = _booking(status: 'PICKED_UP', number: 'TX202607010004');
      final items = [
        current,
        _booking(status: 'DRIVER_ASSIGNED', number: 'TX202607010002'),
        _booking(status: 'COMPLETED', number: 'TX202607010001'),
      ];
      final remaining = DriverUx.remainingTodayTrips(items, current: current);
      expect(remaining.length, 1);
      expect(remaining.first.bookingNumber, 'TX202607010002');
    });

    test('selectCurrentTrip prefers settlement pending over assigned', () {
      final items = [
        _booking(status: 'DRIVER_ASSIGNED', number: 'TX202607010002'),
        _booking(status: 'SETTLEMENT_PENDING', number: 'TX202607010099'),
      ];
      final current = DriverUx.selectCurrentTrip(items);
      expect(current?.status, 'SETTLEMENT_PENDING');
    });

    test(
      'selectCurrentTrip prefers action-required settlement over picked up',
      () {
        final items = [
          _booking(status: 'PICKED_UP', number: 'TX202607010004'),
          _booking(status: 'SETTLEMENT_PENDING', number: 'TX202607010099'),
        ];
        final current = DriverUx.selectCurrentTrip(
          items,
          settlementsByBooking: {
            'TX202607010099': {'commissionStatus': 'PENDING'},
          },
        );
        expect(current?.status, 'SETTLEMENT_PENDING');
      },
    );

    test('selectCurrentTrip prefers picked up over waiting settlement', () {
      final items = [
        _booking(status: 'PICKED_UP', number: 'TX202607010004'),
        _booking(status: 'SETTLEMENT_PENDING', number: 'TX202607010099'),
      ];
      final current = DriverUx.selectCurrentTrip(
        items,
        settlementsByBooking: {
          'TX202607010099': {'commissionStatus': 'RECEIPT_SUBMITTED'},
        },
      );
      expect(current?.status, 'PICKED_UP');
    });

    test('todayPrimaryCtaKey uses settlement-specific labels', () {
      final booking = _booking(status: 'SETTLEMENT_PENDING');
      expect(
        DriverUx.todayPrimaryCtaKey(
          booking,
          settlement: {'commissionStatus': 'PENDING'},
        ),
        'driver_today_cta_settlement_submit',
      );
      expect(
        DriverUx.todayPrimaryCtaKey(
          booking,
          settlement: {'commissionStatus': 'RECEIPT_SUBMITTED'},
        ),
        'driver_today_cta_settlement_waiting',
      );
      expect(
        DriverUx.todayPrimaryCtaKey(booking),
        'driver_today_cta_settlement',
      );
    });
  });

  testWidgets('login success routes to Today shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DriverLoginPage(api: _FakeLoginApi())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'driver@test.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.tap(find.text('로그인 / เข้าสู่ระบบ'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('예정된 운행이 없습니다'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('saved token opens Today shell on login page load', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverLoginPage(api: _FakeLoginApi(initialToken: 'tok')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('기사 로그인\n(เข้าสู่ระบบคนขับ)'), findsNothing);
  });

  testWidgets('expired token on jobs redirects to login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverShellPage(
          api: _FakeJobsApi(
            initialToken: 'tok',
            error: const DriverApiException('Please log in', statusCode: 401),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('기사 로그인\n(เข้าสู่ระบบคนขับ)'), findsOneWidget);
  });

  testWidgets('today page shows remaining trips excluding current card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverTodayPage(
          api: _FakeJobsApi(
            jobs: DriverJobsToday(
              date: '2026-07-01',
              items: [
                _booking(
                  status: 'PICKED_UP',
                  time: '09:00',
                  number: 'TX202607010004',
                ),
                _booking(
                  status: 'DRIVER_ASSIGNED',
                  time: '10:00',
                  number: 'TX202607010002',
                ),
                _booking(
                  status: 'PENDING',
                  time: '12:00',
                  number: 'TX202607010003',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 계속하기 / ดำเนินงานต่อ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('오늘 남은 예약'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.textContaining('오늘 남은 예약'), findsOneWidget);
    expect(find.text('Kim'), findsWidgets);
  });

  testWidgets('settlement pending CTA opens settlement detail only', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = _FakeJobsApi(
      jobs: DriverJobsToday(
        date: '2026-07-01',
        items: [
          _booking(status: 'SETTLEMENT_PENDING', number: 'TX202607010099'),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverTodayPage(
          api: api,
          settlementApi: _FakeSettlementApi(
            settlements: {
              'TX202607010099': {'commissionStatus': 'PENDING'},
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('정산 및 송금증 제출 / ชำระเงินและส่งหลักฐาน'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('정산 및 송금증 제출 / ชำระเงินและส่งหลักฐาน'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('정산 및 송금증 제출 / ชำระเงินและส่งหลักฐาน'));
    await tester.pumpAndSettle();

    expect(api.startRouteCalls, 0);
    expect(find.byType(DriverSettlementDetailPage), findsOneWidget);
    expect(find.byType(DriverBookingDetailPage), findsNothing);
  });

  testWidgets('account page hides terms and privacy placeholder menus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverAccountPage(
          api: _FakeJobsApi(initialToken: 'tok'),
          settlementApi: _FakeSettlementApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('이용약관'), findsNothing);
    expect(find.textContaining('개인정보처리방침'), findsNothing);
  });

  testWidgets('today page fetches phone only for current trip', (tester) async {
    _useTallViewport(tester);
    final api = _TrackingDetailApi(
      jobs: DriverJobsToday(
        date: '2026-07-01',
        items: [
          _booking(
            status: 'DRIVER_ASSIGNED',
            number: 'TX202607010001',
            phone: null,
          ),
          _booking(status: 'CONFIRMED', number: 'TX202607010003', phone: null),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DriverTodayPage(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(api.detailCalls, 1);
    expect(api.detailCallsFor, 'TX202607010001');
  });

  testWidgets('driver shell has four bottom navigation tabs', (tester) async {
    final api = _FakeJobsApi(
      initialToken: 'tok',
      jobs: const DriverJobsToday(date: '2026-07-01', items: []),
    );
    await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('หน้าหลัก'), findsWidgets);
    expect(find.textContaining('งาน'), findsWidgets);
    expect(find.textContaining('การเงิน'), findsOneWidget);
    expect(find.textContaining('บัญชี'), findsOneWidget);
    expect(find.textContaining('운행 기록'), findsNothing);
  });

  testWidgets('today page shows current trip CTA without status mutation', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = _FakeJobsApi(
      jobs: DriverJobsToday(
        date: '2026-07-01',
        items: [
          _booking(status: 'DRIVER_ASSIGNED', actions: ['START_ON_ROUTE']),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DriverTodayPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('픽업 장소로 이동 시작 / เริ่มเดินทางไปยังจุดรับ'), findsNothing);
    expect(find.text('운행 계속하기 / ดำเนินงานต่อ'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('운행 계속하기 / ดำเนินงานต่อ'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('운행 계속하기 / ดำเนินงานต่อ'));
    await tester.pumpAndSettle();

    expect(api.startRouteCalls, 0);
    expect(find.byType(DriverBookingDetailPage), findsOneWidget);
  });

  testWidgets('active job session card opens existing booking detail', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = _FakeJobsApi(
      initialToken: 'tok',
      hasActiveJob: true,
      jobs: DriverJobsToday(
        date: '2026-07-01',
        items: [_booking(status: 'DRIVER_ASSIGNED', number: 'TX202607010099')],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('운행 계속하기 / ดำเนินงานต่อ'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('운행 계속하기 / ดำเนินงานต่อ'));
    await tester.pumpAndSettle();

    expect(find.byType(DriverBookingDetailPage), findsOneWidget);
    expect(find.text('TX202607010099'), findsWidgets);
  });

  testWidgets('driver shell does not expose QR scan menu', (tester) async {
    final api = _FakeJobsApi(
      initialToken: 'tok',
      hasActiveJob: true,
      jobs: DriverJobsToday(
        date: '2026-07-01',
        items: [_booking(status: 'DRIVER_ARRIVED')],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
    expect(find.byType(DriverQrScanPage), findsNothing);
  });

  testWidgets(
    'driver shell fixed status control renders offline and goes online',
    (tester) async {
      final api = _ShellStatusApi(
        status: const DriverStatus(
          driverId: 7,
          active: true,
          online: false,
          status: 'OFFLINE',
          hasActiveJob: false,
        ),
      );

      await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
      await tester.pumpAndSettle();

      expect(find.textContaining('오프라인'), findsWidgets);
      await tester.tap(
        find.widgetWithIcon(FilledButton, Icons.play_circle_fill),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.onlineCalls, 1);
      expect(find.textContaining('온라인'), findsWidgets);
    },
  );

  testWidgets('driver shell offline action asks for confirmation', (
    tester,
  ) async {
    final api = _ShellStatusApi(
      status: const DriverStatus(
        driverId: 7,
        active: true,
        online: true,
        status: 'AVAILABLE',
        hasActiveJob: false,
      ),
    );

    await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithIcon(OutlinedButton, Icons.power_settings_new),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.offlineCalls, 0);

    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(api.offlineCalls, 1);
  });

  testWidgets('driver shell active job disables offline action', (
    tester,
  ) async {
    final api = _ShellStatusApi(
      status: const DriverStatus(
        driverId: 7,
        active: true,
        online: true,
        status: 'AVAILABLE',
        hasActiveJob: true,
      ),
    );

    await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithIcon(OutlinedButton, Icons.power_settings_new),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('운행 중'), findsWidgets);
  });

  testWidgets('driver shell status control shows API error', (tester) async {
    final api = _ShellStatusApi(
      status: const DriverStatus(
        driverId: 7,
        active: true,
        online: false,
        status: 'OFFLINE',
        hasActiveJob: false,
      ),
      onlineError: const DriverApiException('Online failed'),
    );

    await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_circle_fill));
    await tester.pumpAndSettle();

    expect(find.text('Online failed'), findsOneWidget);
  });

  testWidgets(
    'driver shell status control blocks duplicate taps while loading',
    (tester) async {
      final api = _ShellStatusApi(
        status: const DriverStatus(
          driverId: 7,
          active: true,
          online: false,
          status: 'OFFLINE',
          hasActiveJob: false,
        ),
        delayStatusChange: true,
      );

      await tester.pumpWidget(MaterialApp(home: DriverShellPage(api: api)));
      await tester.pumpAndSettle();

      final button = find.byType(FilledButton).first;
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();

      expect(api.onlineCalls, 1);
      api.completePending();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('driver shell status control has no overflow on narrow mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[320, 360]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: DriverShellPage(
            api: _ShellStatusApi(
              status: const DriverStatus(
                driverId: 7,
                active: true,
                online: true,
                status: 'AVAILABLE',
                hasActiveJob: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('driver shell status control explains ready call eligibility', (
    tester,
  ) async {
    final api = _ShellStatusApi(
      status: const DriverStatus(
        driverId: 7,
        active: true,
        online: true,
        status: 'AVAILABLE',
        hasActiveJob: false,
        callEligibility: DriverCallEligibility(
          canReceiveCalls: true,
          reasonCode: DriverCallEligibilityReason.ready,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: DriverStatusControl(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('온라인'), findsWidgets);
    expect(find.textContaining('콜 수신 가능'), findsOneWidget);

    await tester.tap(find.textContaining('콜 수신 가능'));
    await tester.pumpAndSettle();
    expect(find.textContaining('콜 수신 상태'), findsOneWidget);
    expect(find.textContaining('새 예약 콜을 받을 수 있습니다'), findsOneWidget);
  });

  testWidgets('driver shell status control explains settlement blocker', (
    tester,
  ) async {
    final api = _ShellStatusApi(
      status: const DriverStatus(
        driverId: 7,
        active: true,
        online: true,
        status: 'AVAILABLE',
        hasActiveJob: false,
        callEligibility: DriverCallEligibility(
          canReceiveCalls: false,
          reasonCode: DriverCallEligibilityReason.unpaidSettlement,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: DriverStatusControl(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('정산 확인 필요'), findsOneWidget);
    expect(find.textContaining('온라인'), findsWidgets);
  });

  testWidgets('today empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverTodayPage(
          api: _FakeJobsApi(
            jobs: const DriverJobsToday(date: '2026-07-01', items: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('예정된 운행이 없습니다'), findsOneWidget);
  });

  testWidgets('today page shows new calls prompt without inline claim cards', (
    tester,
  ) async {
    final api = _FakeJobsApi(
      initialToken: 'tok',
      online: true,
      openCalls: [_openCall(number: 'TX202607130001')],
    );
    await tester.pumpWidget(MaterialApp(home: DriverTodayPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('새 콜 보기 / ดูงานใหม่'), findsOneWidget);
    expect(find.textContaining('Claim call'), findsNothing);
    expect(find.textContaining('Waiting calls'), findsNothing);
  });

  testWidgets('today page shows settlement blocked new-call guidance', (
    tester,
  ) async {
    final api = _FakeJobsApi(
      initialToken: 'tok',
      online: true,
      openCallBlockedReason: 'UNPAID_SETTLEMENT',
      openCallBlockedMessage:
          'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
    );
    await tester.pumpWidget(
      const MaterialApp(locale: Locale('th'), home: SizedBox.shrink()),
    );
    await tester.pumpWidget(MaterialApp(home: DriverTodayPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่สามารถรับงานใหม่ได้'), findsWidgets);
    expect(find.textContaining('ไปที่หน้าชำระเงิน'), findsOneWidget);
    expect(find.textContaining('Claim call'), findsNothing);
  });

  testWidgets('today settlement blocked guidance has no overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        home: DriverTodayPage(
          api: _FakeJobsApi(
            initialToken: 'tok',
            online: true,
            openCallBlockedReason: 'UNPAID_SETTLEMENT',
            openCallBlockedMessage:
                'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ยังไม่สามารถรับงานใหม่ได้'), findsWidgets);
  });

  testWidgets('jobs page claim open call success refreshes jobs', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = _FakeJobsApi(
      initialToken: 'tok',
      online: true,
      openCalls: [_openCall(number: 'TX202607130002')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DriverJobsPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    final claimButton = find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้');
    await tester.scrollUntilVisible(
      claimButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(claimButton);
    await tester.tap(claimButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.claimCalls, 1);
    expect(find.byType(DriverBookingDetailPage), findsOneWidget);
  });

  testWidgets('jobs page claim conflict shows already claimed message', (
    tester,
  ) async {
    _useTallViewport(tester);
    final api = _FakeJobsApi(
      initialToken: 'tok',
      online: true,
      claimError: const DriverApiException(
        'Already assigned',
        statusCode: 409,
        errorCode: 'ALREADY_ASSIGNED',
      ),
      openCalls: [_openCall(number: 'TX202607130003')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DriverJobsPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    final claimButton = find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้');
    await tester.scrollUntilVisible(
      claimButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(claimButton);
    await tester.tap(claimButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.claimCalls, 1);
    expect(find.textContaining('다른 기사가 먼저 수락했습니다'), findsOneWidget);
  });

  testWidgets('today layout has no horizontal overflow at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: DriverTodayPage(
          api: _FakeJobsApi(
            jobs: DriverJobsToday(
              date: '2026-07-01',
              items: [
                _booking(
                  status: 'DRIVER_ASSIGNED',
                  origin:
                      'Suvarnabhumi Airport Terminal 1 International Arrivals Hall',
                  destination:
                      'Pattaya Beach Road Hotel Resort and Spa Thailand',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('booking detail hides removed customer message action', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['VIEW_DETAILS'],
              phone: '+66123456789',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'), findsNothing);
  });

  testWidgets('cancelled booking is read-only without primary action', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: _FakeDetailApi(
            detail: _booking(status: 'CANCELLED', actions: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('픽업지로 출발 / ออกเดินทางไปรับลูกค้า'), findsNothing);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('stale status error refreshes booking', (tester) async {
    _useTallViewport(tester);
    final api = _FakeDetailApi(
      detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
      arrivedError: const DriverApiException(
        'Invalid status transition',
        errorCode: 'INVALID_STATUS_TRANSITION',
      ),
      refreshed: _booking(
        status: 'DRIVER_ARRIVED',
        actions: ['MARK_PICKED_UP'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverBookingDetailPage(
          bookingNumber: 'TX202607010001',
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, '픽업지 도착 / ถึงจุดรับแล้ว'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '도착 / ถึงแล้ว'));
    await tester.pumpAndSettle();

    expect(find.textContaining('current trip stage'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '고객 탑승 확인 / รับลูกค้าขึ้นรถแล้ว'),
      findsOneWidget,
    );
  });
}

DriverBooking _booking({
  String status = 'DRIVER_ASSIGNED',
  String time = '09:30',
  String number = 'TX202607010001',
  List<String> actions = const ['VIEW_DETAILS'],
  String? phone = '+66123456789',
  String origin = 'BKK Airport',
  String destination = 'Pattaya Hotel',
}) {
  return DriverBooking(
    bookingNumber: number,
    status: status,
    serviceTypeName: 'Airport Pickup',
    pickupDate: '2026-07-01',
    pickupTime: time,
    origin: origin,
    destination: destination,
    passengerCount: 2,
    vehicleTypeName: 'SUV',
    customerDisplayName: 'Kim',
    customerPhone: phone,
    allowedActions: actions,
  );
}

DriverOpenCall _openCall({String number = 'TX202607130001'}) {
  return DriverOpenCall(
    bookingNumber: number,
    status: 'OPEN',
    pickupDate: '2026-07-13',
    pickupTime: '10:30',
    origin: 'BKK Airport',
    destination: 'Pattaya Hotel',
    serviceTypeName: 'Airport pickup',
    vehicleTypeName: 'Van',
    amount: 2500,
    currency: 'THB',
    customerPaymentAmount: 2500,
    customerPaymentCurrency: 'THB',
    companyCommissionAmount: 300,
    companyCommissionCurrency: 'THB',
    driverExpectedIncomeAmount: 2200,
    driverExpectedIncomeCurrency: 'THB',
    passengerCount: 2,
    luggage: const {
      'carriers20Inch': 1,
      'carriers24InchPlus': 2,
      'golfBags': 1,
    },
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeLoginApi extends DriverApiService {
  _FakeLoginApi({String? initialToken}) : _token = initialToken;

  String? _token;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<void> login({required String email, required String password}) async {
    _token = 'test-token';
  }

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<int> getUnreadNotificationCount() async => 0;

  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async => {
    'items': [],
  };

  @override
  Future<Map<String, dynamic>> getRatingSummary() async => {
    'averageRating': null,
    'reviewCount': 0,
  };

  @override
  Future<Map<String, dynamic>> getProfile() async => {
    'name': 'Somchai',
    'phone': '+66812345678',
    'email': 'driver@example.com',
    'vehicle': null,
  };

  @override
  Future<DriverJobsToday> getTodayBookings() async =>
      const DriverJobsToday(date: '2026-07-01', items: []);

  @override
  Future<DriverOpenCalls> getOpenCalls() async =>
      const DriverOpenCalls(items: []);

  @override
  Future<DriverStatus> getStatus() async => DriverStatus(
    driverId: 7,
    active: true,
    online: false,
    status: 'OFFLINE',
    hasActiveJob: false,
  );
}

class _FakeJobsApi extends DriverApiService {
  _FakeJobsApi({
    this.jobs,
    this.openCalls = const [],
    this.openCallBlockedReason,
    this.openCallBlockedMessage,
    this.error,
    this.claimError,
    this.hasActiveJob = false,
    this.online = false,
    String? initialToken,
  }) : _token = initialToken;

  DriverJobsToday? jobs;
  final List<DriverOpenCall> openCalls;
  final String? openCallBlockedReason;
  final String? openCallBlockedMessage;
  final Object? error;
  final Object? claimError;
  final bool hasActiveJob;
  final bool online;
  final String? _token;
  int todayCalls = 0;
  int claimCalls = 0;
  int startRouteCalls = 0;
  int markArrivedCalls = 0;
  int boardingScanCalls = 0;
  int dropoffScanCalls = 0;
  String? lastScannedToken;

  @override
  Future<String?> getSavedToken() async => _token;

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<int> getUnreadNotificationCount() async => 0;

  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async => {
    'items': [],
  };

  @override
  Future<Map<String, dynamic>> getRatingSummary() async => {
    'averageRating': null,
    'reviewCount': 0,
  };

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
  Future<DriverJobsToday> getTodayBookings() async {
    todayCalls += 1;
    if (error != null) throw error!;
    return jobs ?? const DriverJobsToday(date: '2026-07-01', items: []);
  }

  @override
  Future<DriverOpenCalls> getOpenCalls() async {
    return DriverOpenCalls(
      items: openCalls,
      blockedReason: openCallBlockedReason,
      message: openCallBlockedMessage,
    );
  }

  @override
  Future<DriverBooking> claimOpenCall(String bookingNumber) async {
    claimCalls += 1;
    if (claimError != null) throw claimError!;
    return _booking(status: 'DRIVER_ASSIGNED', number: bookingNumber);
  }

  @override
  Future<DriverBooking> startOnRoute(String bookingNumber) async {
    startRouteCalls += 1;
    final current =
        jobs ?? const DriverJobsToday(date: '2026-07-01', items: []);
    final updatedItems = current.items.map((booking) {
      if (booking.bookingNumber != bookingNumber) return booking;
      return _booking(
        status: 'ON_ROUTE',
        number: booking.bookingNumber,
        actions: ['MARK_ARRIVED'],
        time: booking.pickupTime,
        origin: booking.origin,
        destination: booking.destination,
      );
    }).toList();
    jobs = DriverJobsToday(date: current.date, items: updatedItems);
    return updatedItems.firstWhere(
      (booking) => booking.bookingNumber == bookingNumber,
    );
  }

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    return jobs!.items.firstWhere(
      (booking) => booking.bookingNumber == bookingNumber,
    );
  }

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    markArrivedCalls += 1;
    throw UnimplementedError('list view must not call markArrived');
  }

  @override
  Future<DriverBooking> scanBoarding(String bookingNumber, String token) async {
    boardingScanCalls += 1;
    lastScannedToken = token;
    final current = jobs!;
    final updated = _booking(
      status: 'PICKED_UP',
      number: bookingNumber,
      actions: ['COMPLETE_TRIP'],
    );
    jobs = DriverJobsToday(
      date: current.date,
      items: current.items
          .map((item) => item.bookingNumber == bookingNumber ? updated : item)
          .toList(),
    );
    return updated;
  }

  @override
  Future<DriverBooking> scanDropoff(String bookingNumber, String token) async {
    dropoffScanCalls += 1;
    lastScannedToken = token;
    return _booking(status: 'COMPLETED', number: bookingNumber, actions: []);
  }

  @override
  Future<DriverStatus> getStatus() async => DriverStatus(
    driverId: 7,
    active: true,
    online: online,
    status: online ? 'AVAILABLE' : 'OFFLINE',
    hasActiveJob: hasActiveJob,
  );
}

class _ShellStatusApi extends DriverApiService {
  _ShellStatusApi({
    required DriverStatus status,
    this.onlineError,
    this.delayStatusChange = false,
  }) : _status = status;

  DriverStatus _status;
  final Object? onlineError;
  final bool delayStatusChange;
  int onlineCalls = 0;
  int offlineCalls = 0;

  Completer<DriverStatus>? _pending;
  DriverStatus? _pendingStatus;

  @override
  Future<String?> getSavedToken() async => 'tok';

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<int> getUnreadNotificationCount() async => 0;

  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async => {
    'items': [],
  };

  @override
  Future<DriverJobsToday> getTodayBookings() async =>
      const DriverJobsToday(date: '2026-07-01', items: []);

  @override
  Future<DriverOpenCalls> getOpenCalls() async =>
      const DriverOpenCalls(items: []);

  @override
  Future<DriverStatus> getStatus() async => _status;

  @override
  Future<DriverStatus> goOnline() async {
    onlineCalls += 1;
    if (onlineError != null) throw onlineError!;
    return _finishStatusChange(
      DriverStatus(
        driverId: _status.driverId,
        active: _status.active,
        online: true,
        status: 'AVAILABLE',
        hasActiveJob: false,
        lastSeenAt: _status.lastSeenAt,
        callEligibility: const DriverCallEligibility(
          canReceiveCalls: true,
          reasonCode: DriverCallEligibilityReason.ready,
        ),
      ),
    );
  }

  @override
  Future<DriverStatus> goOffline() async {
    offlineCalls += 1;
    return _finishStatusChange(
      DriverStatus(
        driverId: _status.driverId,
        active: _status.active,
        online: false,
        status: 'OFFLINE',
        hasActiveJob: false,
        lastSeenAt: _status.lastSeenAt,
        callEligibility: const DriverCallEligibility(
          canReceiveCalls: false,
          reasonCode: DriverCallEligibilityReason.offline,
        ),
      ),
    );
  }

  Future<DriverStatus> _finishStatusChange(DriverStatus next) {
    if (!delayStatusChange) {
      _status = next;
      return Future.value(_status);
    }
    _pending = Completer<DriverStatus>();
    _pendingStatus = next;
    return _pending!.future.then((value) {
      _status = value;
      return _status;
    });
  }

  void completePending() {
    final pending = _pending;
    final next = _pendingStatus;
    if (pending == null || next == null || pending.isCompleted) return;
    pending.complete(next);
    _pending = null;
    _pendingStatus = null;
  }
}

class _FakeDetailApi extends DriverApiService {
  _FakeDetailApi({
    required DriverBooking detail,
    this.arrivedError,
    this.refreshed,
  }) : _current = detail;

  DriverBooking _current;
  final DriverApiException? arrivedError;
  final DriverBooking? refreshed;
  bool _refreshAfterError = false;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    if (_refreshAfterError && refreshed != null) {
      _current = refreshed!;
      _refreshAfterError = false;
    }
    return _current;
  }

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    if (arrivedError != null) {
      _refreshAfterError = true;
      throw arrivedError!;
    }
    return _current;
  }
}

class _FakeSettlementApi extends DriverSettlementApiService {
  _FakeSettlementApi({this.settlements = const {}});

  final Map<String, Map<String, dynamic>> settlements;

  @override
  Future<List<dynamic>> listSettlements() async => settlements.values.toList();

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    final item = settlements[bookingNumber];
    if (item == null) {
      throw const DriverSettlementApiException('Settlement not found');
    }
    return item;
  }
}

class _TrackingDetailApi extends DriverApiService {
  _TrackingDetailApi({required this.jobs});

  final DriverJobsToday jobs;
  int detailCalls = 0;
  String? detailCallsFor;

  @override
  Future<DriverJobsToday> getTodayBookings() async => jobs;

  @override
  Future<DriverOpenCalls> getOpenCalls() async =>
      const DriverOpenCalls(items: []);

  @override
  Future<String?> getDriverDisplayName() async => 'Somchai';

  @override
  Future<int> getUnreadNotificationCount() async => 0;

  @override
  Future<Map<String, dynamic>> listNotifications({bool? unreadOnly}) async => {
    'items': [],
  };

  @override
  Future<DriverStatus> getStatus() async => DriverStatus(
    driverId: 7,
    active: true,
    online: false,
    status: 'OFFLINE',
    hasActiveJob: false,
  );

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    detailCalls += 1;
    detailCallsFor = bookingNumber;
    return jobs.items.firstWhere(
      (booking) => booking.bookingNumber == bookingNumber,
    );
  }
}
