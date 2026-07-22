import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/controllers/booking_wizard_controller.dart';
import 'package:frontend/features/booking/models/booking_create_result.dart';
import 'package:frontend/features/booking/models/urgent_negotiation_status.dart';
import 'package:frontend/features/booking/pages/urgent_booking_flow_page.dart';
import 'package:frontend/features/booking/services/booking_api_service.dart';
import 'package:frontend/features/booking/services/customer_urgent_negotiation_socket_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookingWizardController urgent pickup window', () {
    final fixedNow = DateTime(2026, 7, 23, 10, 0);

    BookingWizardController controller() {
      return BookingWizardController(now: () => fixedNow);
    }

    test('detects pickup within two hours as urgent window', () {
      final c = controller();
      final urgentPickup = DateTime(2026, 7, 23, 11, 30);
      expect(c.isUrgentPickupWindow(urgentPickup), isTrue);
      expect(c.isStandardPickupAllowed(urgentPickup), isFalse);
    });

    test('detects pickup after two hours as standard only', () {
      final c = controller();
      final standardPickup = DateTime(2026, 7, 23, 12, 30);
      expect(c.isUrgentPickupWindow(standardPickup), isFalse);
      expect(c.isStandardPickupAllowed(standardPickup), isTrue);
    });
  });

  group('UrgentBookingFlowPage', () {
    const result = BookingCreateResult(
      bookingId: 10,
      bookingNumber: 'TX202607230001',
      guestAccessToken: 'guest-token',
      boardingQrToken: 'boarding-token',
      chatRoomCode: 'CHAT-TX202607230001',
      status: 'OPEN',
      paymentMethod: 'PAY_DRIVER',
      paymentStatus: 'UNPAID',
      totalAmount: 1500,
      currency: 'THB',
      trustMessage: '',
      isUrgentRequest: true,
    );

    Future<void> pumpFlow(
      WidgetTester tester, {
      required FakeCustomerUrgentApi api,
      required FakeCustomerUrgentSocket socket,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: Consumer<LocaleState>(
            builder: (context, localeState, _) {
              return MaterialApp(
                locale: Locale(localeState.languageCode),
                supportedLocales: AppLocalizations.supportedLanguages
                    .map((code) => Locale(code))
                    .toList(),
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: UrgentBookingFlowPage(
                  result: result,
                  customerPhone: '01012345678',
                  apiService: api,
                  socketService: socket,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    test('shouldPollFallback stops when socket subscription is active', () {
      expect(
        UrgentBookingFlowPage.shouldPollFallback(
          hasActiveSubscription: true,
          isTerminalPhase: false,
        ),
        isFalse,
      );
    });

    test('shouldPollFallback resumes when socket subscription is inactive', () {
      expect(
        UrgentBookingFlowPage.shouldPollFallback(
          hasActiveSubscription: false,
          isTerminalPhase: false,
        ),
        isTrue,
      );
    });

    test('shouldPollFallback stops in terminal phases', () {
      expect(
        UrgentBookingFlowPage.shouldPollFallback(
          hasActiveSubscription: false,
          isTerminalPhase: true,
        ),
        isFalse,
      );
    });

    testWidgets('polling runs only as fallback when socket is not subscribed', (
      tester,
    ) async {
      final api = FakeCustomerUrgentApi(
        status: const UrgentNegotiationStatus(
          bookingNumber: 'TX202607230001',
          bookingId: 10,
          bookingStatus: 'OPEN',
          negotiationId: 1,
          status: 'BROADCASTING',
          attemptCount: 0,
        ),
      );
      final socket = FakeCustomerUrgentSocket(subscriptionActive: false);

      await pumpFlow(tester, api: api, socket: socket);
      expect(api.statusFetchCount, 1);

      await tester.pump(UrgentBookingFlowPage.pollInterval);
      expect(api.statusFetchCount, 2);

      socket.setSubscriptionActive(true);
      await tester.pump();

      await tester.pump(UrgentBookingFlowPage.pollInterval);
      expect(api.statusFetchCount, 2);

      socket.setSubscriptionActive(false);
      await tester.pump();

      await tester.pump(UrgentBookingFlowPage.pollInterval);
      expect(api.statusFetchCount, 3);
    });

    test('phaseFromStatus maps awaiting customer to eta proposed', () {
      expect(
        UrgentBookingFlowPage.phaseFromStatus(
          const UrgentNegotiationStatus(
            bookingNumber: 'TX202607230001',
            bookingStatus: 'OPEN',
            negotiationId: 1,
            status: 'AWAITING_CUSTOMER',
            attemptCount: 1,
            proposedEtaMinutes: 25,
          ),
        ),
        UrgentFlowPhase.etaProposed,
      );
    });

    testWidgets('shows searching screen initially', (tester) async {
      final api = FakeCustomerUrgentApi(
        status: const UrgentNegotiationStatus(
          bookingNumber: 'TX202607230001',
          bookingId: 10,
          bookingStatus: 'OPEN',
          negotiationId: 1,
          status: 'BROADCASTING',
          attemptCount: 0,
        ),
      );
      final socket = FakeCustomerUrgentSocket();

      await pumpFlow(tester, api: api, socket: socket);

      expect(find.text('기사를 찾고 있습니다'), findsOneWidget);
    });

    testWidgets('eta proposed socket switches to accept/reject UI', (
      tester,
    ) async {
      final api = FakeCustomerUrgentApi(
        status: const UrgentNegotiationStatus(
          bookingNumber: 'TX202607230001',
          bookingId: 10,
          bookingStatus: 'OPEN',
          negotiationId: 1,
          status: 'AWAITING_CUSTOMER',
          attemptCount: 1,
          proposedEtaMinutes: 18,
        ),
      );
      final socket = FakeCustomerUrgentSocket();

      await pumpFlow(tester, api: api, socket: socket);

      socket.simulateEtaProposed({'etaMinutes': 18});
      await tester.pump();

      expect(find.textContaining('18'), findsWidgets);
      expect(find.text('수락'), findsOneWidget);
      expect(find.text('거절'), findsOneWidget);
    });

    testWidgets('reject decision shows retry prompt', (tester) async {
      final api = FakeCustomerUrgentApi(
        status: const UrgentNegotiationStatus(
          bookingNumber: 'TX202607230001',
          bookingId: 10,
          bookingStatus: 'OPEN',
          negotiationId: 1,
          status: 'AWAITING_CUSTOMER',
          attemptCount: 1,
          proposedEtaMinutes: 20,
        ),
        decisionResult: const UrgentDecisionResult(
          bookingNumber: 'TX202607230001',
          decision: 'REJECT',
          status: 'BROADCASTING',
          bookingStatus: 'OPEN',
          attemptCount: 1,
        ),
      );
      final socket = FakeCustomerUrgentSocket();

      await pumpFlow(tester, api: api, socket: socket);

      socket.simulateEtaProposed({'etaMinutes': 20});
      await tester.pump();

      await tester.tap(find.text('거절'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('더 빠른 기사를 찾아볼까요?'), findsOneWidget);
    });

    testWidgets('cancelled socket shows exhausted message', (tester) async {
      final api = FakeCustomerUrgentApi(
        status: const UrgentNegotiationStatus(
          bookingNumber: 'TX202607230001',
          bookingId: 10,
          bookingStatus: 'CANCELLED',
          negotiationId: 1,
          status: 'CANCELLED',
          attemptCount: 3,
          closedReason: 'URGENT_NEGOTIATION_EXHAUSTED',
        ),
      );
      final socket = FakeCustomerUrgentSocket();

      await pumpFlow(tester, api: api, socket: socket);

      socket.simulateCancelled({});
      await tester.pump();

      expect(
        find.textContaining('가까운 곳에 대기중인 기사가 없습니다'),
        findsOneWidget,
      );
    });
  });

  group('urgent confirm dialog copy', () {
    testWidgets('dialog shows confirm body text', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleState(),
          child: Consumer<LocaleState>(
            builder: (context, localeState, _) {
              return MaterialApp(
                locale: Locale(localeState.languageCode),
                supportedLocales: AppLocalizations.supportedLanguages
                    .map((code) => Locale(code))
                    .toList(),
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () async {
                        final l10n = context.l10n;
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l10n.t('customer_urgent_confirm_title')),
                            content: Text(l10n.t('customer_urgent_confirm_body')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l10n.t('ui_cancel')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l10n.t('customer_urgent_confirm_submit')),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('open'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('긴급 요청 확인'), findsOneWidget);
      expect(find.textContaining('배차에 시간이 다소 소요'), findsOneWidget);
      expect(find.text('확정'), findsOneWidget);
    });
  });
}

class FakeCustomerUrgentApi extends BookingApiService {
  FakeCustomerUrgentApi({
    required this.status,
    this.decisionResult,
  }) : super.test(client: _FakeHttpClient(), baseUrl: 'http://test');

  final UrgentNegotiationStatus status;
  final UrgentDecisionResult? decisionResult;
  int statusFetchCount = 0;

  @override
  Future<UrgentNegotiationStatus> getUrgentNegotiation({
    required String bookingNumber,
    String? guestAccessToken,
  }) async {
    statusFetchCount += 1;
    return status;
  }

  @override
  Future<UrgentDecisionResult> submitUrgentDecision({
    required String bookingNumber,
    required String decision,
    String? guestAccessToken,
  }) async {
    return decisionResult ??
        UrgentDecisionResult(
          bookingNumber: bookingNumber,
          decision: decision,
          status: decision == 'ACCEPT' ? 'CONFIRMED' : 'BROADCASTING',
          bookingStatus: decision == 'ACCEPT' ? 'DRIVER_ASSIGNED' : 'OPEN',
        );
  }
}

class FakeCustomerUrgentSocket extends CustomerUrgentNegotiationSocketService {
  FakeCustomerUrgentSocket({this.subscriptionActive = false});

  bool subscriptionActive;

  @override
  bool get hasActiveSubscription => subscriptionActive;

  void setSubscriptionActive(bool active) {
    subscriptionActive = active;
    onSubscriptionStateChanged?.call();
  }

  void simulateEtaProposed(Map<String, dynamic> payload) {
    onEtaProposed?.call(payload);
  }

  void simulateCancelled(Map<String, dynamic> payload) {
    onCancelled?.call(payload);
  }

  @override
  void disconnect() {}
}

class _FakeHttpClient implements http.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
