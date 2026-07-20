import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/pages/booking_complete_page.dart';
import 'package:frontend/features/booking/pages/guest_booking_lookup_page.dart';
import 'package:frontend/features/booking/services/booking_chat_api.dart';
import 'package:frontend/features/booking/services/guest_booking_lookup_service.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/booking/models/guest_booking_lookup_result.dart';
import 'package:frontend/features/driver/driver_ux.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/pages/driver_jobs_page.dart';
import 'package:frontend/features/driver/pages/driver_today_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_settlement/pages/driver_settlement_list_page.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';

import 'support/driver_ux_qa_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PR72 driver shell QA', () {
    testWidgets('logged-in shell shows four Thai bottom tabs', (tester) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(390, 844),
      );
      final api = QaDriverApi(
        jobs: DriverJobsToday(
          date: '2026-07-01',
          items: [qaBooking(status: 'DRIVER_ASSIGNED')],
        ),
      );
      await tester.pumpWidget(DriverUxQaHarness.shell(api: api));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('หน้าหลัก'), findsWidgets);
      expect(find.textContaining('งาน'), findsWidgets);
      expect(find.textContaining('การเงิน'), findsOneWidget);
      expect(find.textContaining('บัญชี'), findsOneWidget);
      expect(find.text('알림'), findsNothing);
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('tab navigation switches pages without stack issues', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(390, 844),
      );
      final api = QaDriverApi(
        jobs: const DriverJobsToday(date: '2026-07-01', items: []),
        openCalls: [qaOpenCall()],
        online: true,
      );
      final settlementApi = QaSettlementApi(
        settlements: {
          'TX202607010099': {
            'bookingNumber': 'TX202607010099',
            'commissionStatus': 'PENDING',
          },
        },
      );
      await tester.pumpWidget(
        DriverUxQaHarness.shell(api: api, settlementApi: settlementApi),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('업무\n(งาน)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('새 콜'), findsWidgets);
      expect(find.byType(DriverJobsPage), findsOneWidget);

      await tester.tap(find.text('정산\n(การเงิน)'));
      await tester.pumpAndSettle();
      expect(find.byType(DriverSettlementListPage), findsOneWidget);

      await tester.tap(find.text('내 정보\n(บัญชี)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('알림'), findsWidgets);

      await tester.tap(find.text('홈\n(หน้าหลัก)'));
      await tester.pumpAndSettle();
      expect(find.byType(DriverTodayPage), findsOneWidget);
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('settlement badge hidden without pending settlements', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(390, 844),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.shell(
          api: QaDriverApi(
            jobs: const DriverJobsToday(date: '2026-07-01', items: []),
          ),
          settlementApi: QaSettlementApi(settlements: const {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('1'),
        ),
        findsNothing,
      );
    });

    testWidgets('settlement badge shows pending settlement count', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(390, 844),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.shell(
          api: QaDriverApi(
            jobs: const DriverJobsToday(date: '2026-07-01', items: []),
          ),
          settlementApi: QaSettlementApi(
            settlements: {
              'TX202607010099': {
                'bookingNumber': 'TX202607010099',
                'commissionStatus': 'PENDING',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 20; attempt++) {
        if (find
            .descendant(
              of: find.byType(NavigationBar),
              matching: find.text('1'),
            )
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    test('settlement badge counter includes pending commission status', () {
      expect(
        DriverUx.countPendingSettlements(const [
          {'commissionStatus': 'PENDING'},
        ]),
        1,
      );
    });

    for (final size in DriverUxQaHarness.viewports) {
      for (final scale in DriverUxQaHarness.textScales) {
        testWidgets(
          'shell responsive ${size.width}x${size.height} scale $scale',
          (tester) async {
            await DriverUxQaHarness.configureViewport(
              tester,
              size: size,
              textScale: scale,
            );
            await tester.pumpWidget(
              DriverUxQaHarness.shell(
                api: QaDriverApi(
                  jobs: const DriverJobsToday(date: '2026-07-01', items: []),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            DriverUxQaHarness.expectNoOverflow(tester);
          },
        );
      }
    }
  });

  group('PR72 home QA', () {
    testWidgets('fixture A: empty job with new calls prompt, no inline claim', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      final api = QaDriverApi(
        jobs: const DriverJobsToday(date: '2026-07-01', items: []),
        openCalls: [
          qaOpenCall(),
          qaOpenCall(number: 'TX202607130002'),
        ],
        online: true,
      );
      var jobsTabRequested = false;
      await tester.pumpWidget(
        DriverUxQaHarness.page(
          DriverTodayPage(
            api: api,
            onNavigateToJobs: () => jobsTabRequested = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('새 콜 보기 / ดูงานใหม่'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
        findsNothing,
      );
      await tester.tap(find.textContaining('새 콜 보기 / ดูงานใหม่'));
      expect(jobsTabRequested, isTrue);
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('fixture B: current job card with single primary CTA', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      final booking = qaBooking(status: 'PICKED_UP');
      await tester.pumpWidget(
        DriverUxQaHarness.page(
          DriverTodayPage(
            api: QaDriverApi(
              jobs: DriverJobsToday(date: '2026-07-01', items: [booking]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('지금 할 일'), findsOneWidget);
      expect(find.text('09:30'), findsWidgets);
      expect(find.text('BKK Airport'), findsWidgets);
      expect(find.text('Pattaya Hotel'), findsWidgets);
      expect(find.text('운행 계속하기 / ดำเนินงานต่อ'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, '운행 계속하기 / ดำเนินงานต่อ'),
        findsOneWidget,
      );
      DriverUxQaHarness.expectPrimaryCtaHeight(
        tester,
        find.widgetWithText(FilledButton, '운행 계속하기 / ดำเนินงานต่อ'),
      );
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('fixture D: settlement blocked banner prioritized', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(
          DriverTodayPage(
            api: QaDriverApi(
              openCalls: [qaOpenCall()],
              openCallBlockedReason: 'UNPAID_SETTLEMENT',
              openCallBlockedMessage:
                  'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่น',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ยังไม่สามารถรับงานใหม่ได้'), findsWidgets);
      expect(find.textContaining('ไปที่หน้าชำระเงิน'), findsOneWidget);
      expect(find.textContaining('새 콜 보기 / ดูงานใหม่'), findsNothing);
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('fixture E: waiting for admin settlement copy', (tester) async {
      final booking = qaBooking(
        status: 'SETTLEMENT_PENDING',
        number: 'TX202607010099',
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(
          DriverTodayPage(
            api: QaDriverApi(
              jobs: DriverJobsToday(date: '2026-07-01', items: [booking]),
            ),
            settlementApi: QaSettlementApi(
              settlements: {
                'TX202607010099': {
                  'bookingNumber': 'TX202607010099',
                  'commissionStatus': 'RECEIPT_SUBMITTED',
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('입금 확인 대기 중 / รอตรวจสอบการชำระเงิน'), findsOneWidget);
    });

    testWidgets('home loading and error states expose retry', (tester) async {
      final api = QaDriverApi(
        loadError: const DriverApiException('Network down'),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(DriverTodayPage(api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Network down'), findsNothing);
      expect(find.textContaining('다시 시도 / ลองอีกครั้ง'), findsOneWidget);
    });
  });

  group('PR72 jobs QA', () {
    testWidgets('three tabs and open call card without commission', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      final api = QaDriverApi(online: true, openCalls: [qaOpenCall()]);
      await tester.pumpWidget(DriverUxQaHarness.page(DriverJobsPage(api: api)));
      await tester.pumpAndSettle();
      if (find.textContaining('온라인 상태에서만').evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('새 콜'), findsWidgets);
      expect(find.textContaining('내 업무'), findsOneWidget);
      expect(find.textContaining('지난 업무'), findsOneWidget);
      expect(find.textContaining('10:30'), findsWidgets);
      expect(find.textContaining('BKK Airport'), findsWidgets);
      expect(find.textContaining('Pattaya Hotel'), findsWidgets);
      expect(find.textContaining('고객 결제 총액'), findsWidgets);
      expect(find.textContaining('회사에 납부할 수수료'), findsNothing);
      expect(find.textContaining('기사 예상 수입'), findsNothing);
      expect(find.textContaining('รับงานนี้'), findsWidgets);
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('claim dialog uses mock API and blocks duplicate taps', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(800, 1400),
      );
      final api = QaDriverApi(
        online: true,
        openCalls: [qaOpenCall()],
        claimDelay: const Duration(milliseconds: 200),
      );
      await tester.pumpWidget(DriverUxQaHarness.page(DriverJobsPage(api: api)));
      await tester.pumpAndSettle();

      final claimButton = find.widgetWithText(
        FilledButton,
        '이 콜 수락 / รับงานนี้',
      );
      await tester.scrollUntilVisible(
        claimButton,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(claimButton);
      await tester.tap(claimButton.first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
        ),
      );
      await tester.pump();
      expect(api.claimCalls, 1);
      await tester.tap(claimButton.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.claimCalls, 1);
      await tester.pumpAndSettle();
      expect(api.todayCalls, greaterThan(1));
    });

    testWidgets('already claimed and network errors show friendly copy', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(800, 1400),
      );
      final conflictApi = QaDriverApi(
        online: true,
        openCalls: [qaOpenCall()],
        claimError: const DriverApiException(
          'Already assigned',
          statusCode: 409,
          errorCode: 'ALREADY_ASSIGNED',
        ),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(DriverJobsPage(api: conflictApi)),
      );
      await tester.pumpAndSettle();
      final claimButton = find.widgetWithText(
        FilledButton,
        '이 콜 수락 / รับงานนี้',
      );
      await tester.scrollUntilVisible(
        claimButton,
        500,
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
      expect(find.textContaining('다른 기사가 먼저 수락했습니다'), findsOneWidget);
      expect(find.textContaining('ALREADY_ASSIGNED'), findsNothing);

      final networkApi = QaDriverApi(
        online: true,
        openCalls: [qaOpenCall(number: 'TX202607130002')],
        claimError: const DriverApiException('socket hang up'),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(DriverJobsPage(api: networkApi)),
      );
      await tester.pumpAndSettle();
      final claim2 = find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้');
      await tester.scrollUntilVisible(
        claim2,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(claim2);
      await tester.tap(claim2);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('socket hang up'), findsNothing);
    });

    testWidgets('settlement blocked state on jobs tab', (tester) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(
          DriverJobsPage(
            api: QaDriverApi(
              online: true,
              openCallBlockedReason: 'UNPAID_SETTLEMENT',
              openCallBlockedMessage: 'ยังไม่สามารถรับงานใหม่ได้',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังไม่สามารถรับงานใหม่ได้'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, '이 콜 수락 / รับงานนี้'),
        findsNothing,
      );
    });
  });

  group('PR72 booking detail QA', () {
    test('seven-step mapping for active statuses', () {
      final assigned = qaBooking(
        status: 'DRIVER_ASSIGNED',
        actions: ['ACCEPT_BOOKING'],
      );
      expect(DriverUx.tripStepInfo(assigned)?.step, 2);
      expect(DriverUx.tripStepInfo(assigned)?.totalSteps, 7);

      final onRoute = qaBooking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']);
      expect(DriverUx.tripStepInfo(onRoute)?.step, 4);

      final pickedUp = qaBooking(status: 'PICKED_UP', actions: ['END_TRIP']);
      expect(DriverUx.tripStepInfo(pickedUp)?.step, 6);

      expect(DriverUx.tripStepInfo(qaBooking(status: 'CANCELLED')), isNull);
    });

    testWidgets('detail hides customer chat and shows phone CTA', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
        textScale: 1.3,
      );
      await tester.pumpWidget(
        DriverUxQaHarness.page(
          DriverBookingDetailPage(
            bookingNumber: 'TX202607010001',
            api: _DetailApi(
              detail: qaBooking(
                status: 'ON_ROUTE',
                actions: ['VIEW_DETAILS', 'MARK_ARRIVED'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ขั้นตอนที่'), findsWidgets);
      expect(find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('โทรหาลูกค้า'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('고객에게 전화 / โทรหาลูกค้า'), findsWidgets);
      expect(find.textContaining('DRIVER_ASSIGNED'), findsNothing);
      DriverUxQaHarness.expectNoOverflow(tester);
    });
  });

  group('PR72 customer chat removal QA', () {
    testWidgets('booking complete hides chat entry', (tester) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BookingCompletePage(
            result: BookingCreateResult(
              bookingId: 1,
              bookingNumber: 'TX202607010001',
              status: 'DRIVER_ASSIGNED',
              paymentMethod: 'PAY_DRIVER',
              paymentStatus: 'UNPAID',
              totalAmount: 1500,
              currency: 'THB',
              guestAccessToken: 'guest-token',
              chatRoomCode: 'CHAT-TX202607010001',
              boardingQrToken: 'boarding-token',
              trustMessage: 'Booking received',
            ),
            serviceLabel: 'Airport Pickup',
            originLabel: 'BKK Airport',
            destinationLabel: 'Pattaya Hotel',
            enableCustomerTools: true,
            chatApi: _StubBookingChatApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Booking chat'), findsNothing);
      expect(find.textContaining('CHAT_NOT_ACCESSIBLE'), findsNothing);
      DriverUxQaHarness.expectNoOverflow(tester);
    });

    testWidgets('guest lookup hides chat and pickup alert actions', (
      tester,
    ) async {
      await DriverUxQaHarness.configureViewport(
        tester,
        size: const Size(360, 800),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GuestBookingLookupPage(
            lookupService: _StubGuestLookupService(),
            enableCustomerTools: true,
            bookingChatApi: _StubBookingChatApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('guest_lookup_booking_number')),
        'TX202607010001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guest_lookup_phone')),
        '+66123456789',
      );
      await tester.tap(find.text('Find booking'));
      await tester.pumpAndSettle();

      expect(find.text('Booking chat'), findsNothing);
      expect(find.textContaining('conversationId'), findsNothing);
      DriverUxQaHarness.expectNoOverflow(tester);
    });
  });
}

class _DetailApi extends DriverApiService {
  _DetailApi({required this.detail});

  final DriverBooking detail;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async => detail;

  @override
  Future<DriverStatus> getStatus() async => DriverStatus(
    driverId: 7,
    active: true,
    online: true,
    status: 'ONLINE',
    hasActiveJob: true,
  );
}

class _StubBookingChatApi extends BookingChatApi {
  @override
  Future<Map<String, dynamic>> getRoom({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    throw const BookingChatApiException('Chat not accessible', statusCode: 410);
  }
}

class _StubGuestLookupService extends GuestBookingLookupService {
  @override
  Future<GuestBookingLookupResult?> loadCached() async => null;

  @override
  Future<GuestBookingLookupResult> lookup({
    required String bookingNumber,
    required String phone,
  }) async {
    return GuestBookingLookupResult(
      bookingNumber: bookingNumber,
      status: 'DRIVER_ASSIGNED',
      scheduledPickupAt: '2026-07-01T09:30:00',
      serviceTypeName: 'Airport Pickup',
      originAddress: 'BKK Airport',
      destinationAddress: 'Pattaya Hotel',
      totalAmount: 2500,
      currency: 'THB',
      paymentMethod: 'PAY_DRIVER',
      guestAccessToken: 'guest-token',
      guestAccessExpiresAt: null,
      capabilities: const GuestBookingCapabilities(
        chatAvailable: true,
        notificationsAvailable: true,
        dropoffQrIssueAvailable: false,
        reviewAvailable: false,
        trackingAvailable: true,
        boardingQrRecoverable: true,
        boardingQrPreviouslyIssued: true,
      ),
      customerPhone: phone,
    );
  }
}
