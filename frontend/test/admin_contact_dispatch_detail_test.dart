import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_booking_detail_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/features/admin_dispatch/utils/admin_contact_dispatch_ux.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_theme.dart';

class _ContactDetailApi extends AdminDispatchApiService {
  _ContactDetailApi({
    required this.detail,
    this.verifyError,
    this.retryError,
  });

  Map<String, dynamic> detail;
  final Object? verifyError;
  final Object? retryError;
  int loadCount = 0;
  int verifyCount = 0;
  int retryCount = 0;

  static Map<String, dynamic> fixture({
    String status = 'OPEN',
    String contactStatus = 'VERIFIED',
    String? channel = 'LINE',
    String? requestedAt = '2026-09-26T01:00:00.000Z',
    String? verifiedAt,
    String dispatchState = 'NOT_APPLICABLE',
    bool retryable = false,
    String mode = 'STANDARD',
    bool isUrgent = false,
    List<String> allowedActions = const ['ASSIGN_DRIVER'],
  }) {
    return {
      'bookingNumber': 'TX202609260099',
      'status': status,
      'isUrgentRequest': isUrgent,
      'allowedActions': allowedActions,
      'contactDispatch': {
        'state': dispatchState,
        'persisted': dispatchState == 'DELIVERY_RETRY_NEEDED' ||
            dispatchState == 'DELIVERY_ATTEMPTED',
        'deliveryAttempted': dispatchState == 'DELIVERY_ATTEMPTED',
        'retryable': retryable,
        'mode': mode,
      },
      'scheduledPickupAt': '2026-09-26T03:00:00.000Z',
      'route': {
        'origin': {'address': 'BKK', 'name': 'BKK'},
        'destination': {'address': 'Pattaya', 'name': 'Pattaya'},
      },
      'customer': {
        'name': 'QA Kim',
        'phone': '+66800000001',
        'contactStatus': contactStatus,
        'contactChannel': channel,
        'contactRequestedAt': requestedAt,
        'contactVerifiedAt': verifiedAt,
      },
      'pricing': {
        'paymentMethod': 'PAY_DRIVER',
        'paymentStatus': 'UNPAID',
        'totalAmount': 1200,
        'currency': 'THB',
        'chargeItems': const [],
      },
      'vehicle': {'typeCode': 'VAN', 'typeName': 'Van', 'count': 1},
      'passengers': {'adults': 1, 'children': 0, 'infants': 0},
      'luggage': {
        'carriers20Inch': 0,
        'carriers24InchPlus': 0,
        'golfBags': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    loadCount += 1;
    return Map<String, dynamic>.from(detail);
  }

  @override
  Future<Map<String, dynamic>> listBookingNotes(
    String bookingNumber, {
    int page = 1,
    int limit = 20,
  }) async {
    return {'items': [], 'page': 1, 'limit': 20, 'total': 0};
  }

  @override
  Future<Map<String, dynamic>> verifyContactConnection(
    String bookingNumber,
  ) async {
    verifyCount += 1;
    if (verifyError != null) throw verifyError!;
    detail = fixture(
      contactStatus: 'VERIFIED',
      verifiedAt: '2026-09-26T01:10:00.000Z',
      dispatchState: 'DISPATCH_PENDING',
      retryable: true,
      allowedActions: const ['ASSIGN_DRIVER', 'RETRY_CONTACT_DISPATCH'],
    );
    return {'dispatchStarted': true};
  }

  @override
  Future<Map<String, dynamic>> retryContactDispatch(
    String bookingNumber,
  ) async {
    retryCount += 1;
    if (retryError != null) throw retryError!;
    detail = fixture(
      dispatchState: 'DELIVERY_ATTEMPTED',
      retryable: false,
      allowedActions: const ['ASSIGN_DRIVER'],
    );
    return {'dispatchStarted': true};
  }
}

Future<void> _pumpPage(WidgetTester tester, _ContactDetailApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('en'),
      localizationsDelegates: [
        AppLocalizationsDelegate('en'),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: AdminBookingDetailPage(
        bookingNumber: 'TX202609260099',
        api: api,
        onChanged: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('CTA helpers match allowedActions and derived state', () {
    expect(
      AdminContactDispatchUx.showVerifyCta(
        contactStatus: 'CONFIRM_REQUESTED',
        allowedActions: const ['VERIFY_CONTACT'],
      ),
      isTrue,
    );
    expect(
      AdminContactDispatchUx.showRetryCta(
        retryable: true,
        allowedActions: const ['RETRY_CONTACT_DISPATCH'],
        state: 'DELIVERY_ATTEMPTED',
      ),
      isFalse,
    );
    expect(
      AdminContactDispatchUx.showRetryCta(
        retryable: true,
        allowedActions: const ['RETRY_CONTACT_DISPATCH'],
        state: 'DISPATCH_PENDING',
      ),
      isTrue,
    );
  });

  testWidgets('CONFIRM_REQUESTED shows translated status and verify CTA only', (
    tester,
  ) async {
    final api = _ContactDetailApi(
      detail: _ContactDetailApi.fixture(
        contactStatus: 'CONFIRM_REQUESTED',
        dispatchState: 'WAITING_CONTACT',
        allowedActions: const ['ASSIGN_DRIVER', 'VERIFY_CONTACT'],
      ),
    );
    await _pumpPage(tester, api);
    expect(find.text('Customer asked to confirm'), findsOneWidget);
    expect(find.text('LINE'), findsOneWidget);
    expect(find.byKey(const Key('admin-contact-verify')), findsOneWidget);
    expect(find.byKey(const Key('admin-contact-dispatch-retry')), findsNothing);
    expect(
      find.textContaining('does not guarantee the driver app received'),
      findsOneWidget,
    );
  });

  testWidgets('NOT_APPLICABLE, delivered, and NOT_OPEN hide retry', (
    tester,
  ) async {
    for (final state in ['NOT_APPLICABLE', 'DELIVERY_ATTEMPTED', 'NOT_OPEN']) {
      final api = _ContactDetailApi(
        detail: _ContactDetailApi.fixture(
          status: state == 'NOT_OPEN' ? 'DRIVER_ASSIGNED' : 'OPEN',
          dispatchState: state,
        ),
      );
      await _pumpPage(tester, api);
      expect(find.byKey(const Key('admin-contact-dispatch-retry')), findsNothing);
    }
  });

  testWidgets('non-open contact flow hides verify and retry actions', (tester) async {
    final api = _ContactDetailApi(
      detail: _ContactDetailApi.fixture(
        status: 'DRIVER_ASSIGNED',
        contactStatus: 'CONFIRM_REQUESTED',
        dispatchState: 'NOT_OPEN',
        retryable: false,
        allowedActions: const ['REASSIGN_DRIVER'],
      ),
    );
    await _pumpPage(tester, api);
    expect(find.byKey(const Key('admin-contact-verify')), findsNothing);
    expect(find.byKey(const Key('admin-contact-dispatch-retry')), findsNothing);
  });

  testWidgets('STANDARD label is shown for open-call mode', (tester) async {
    final standard = _ContactDetailApi(
      detail: _ContactDetailApi.fixture(mode: 'STANDARD'),
    );
    await _pumpPage(tester, standard);
    expect(find.textContaining('Open-call notification'), findsOneWidget);
  });

  testWidgets('URGENT label is shown for urgent-call mode', (tester) async {
    final urgent = _ContactDetailApi(
      detail: _ContactDetailApi.fixture(mode: 'URGENT', isUrgent: true),
    );
    await _pumpPage(tester, urgent);
    final urgentLabel = find.textContaining('Urgent-call notification');
    await tester.scrollUntilVisible(
      urgentLabel,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(urgentLabel, findsOneWidget);
  });

  testWidgets('retry success reloads detail', (tester) async {
    final api = _ContactDetailApi(
      detail: _ContactDetailApi.fixture(
        dispatchState: 'DELIVERY_RETRY_NEEDED',
        retryable: true,
        allowedActions: const ['ASSIGN_DRIVER', 'RETRY_CONTACT_DISPATCH'],
      ),
    );
    await _pumpPage(tester, api);
    expect(api.loadCount, 1);
    await tester.ensureVisible(find.byKey(const Key('admin-contact-dispatch-retry')));
    await tester.tap(find.byKey(const Key('admin-contact-dispatch-retry')));
    await tester.pumpAndSettle();
    expect(api.retryCount, 1);
    expect(api.loadCount, 2);
    expect(find.text('Driver notification retry started'), findsOneWidget);
    expect(find.byKey(const Key('admin-contact-dispatch-retry')), findsNothing);
  });

  testWidgets('409 retry error uses user-facing copy', (tester) async {
    final api = _ContactDetailApi(
      detail: _ContactDetailApi.fixture(
        dispatchState: 'DELIVERY_RETRY_NEEDED',
        retryable: true,
        allowedActions: const ['ASSIGN_DRIVER', 'RETRY_CONTACT_DISPATCH'],
      ),
      retryError: const AdminDispatchApiException(
        'already delivered',
        errorCode: 'CONTACT_DISPATCH_ALREADY_DELIVERED',
      ),
    );
    await _pumpPage(tester, api);
    await tester.ensureVisible(find.byKey(const Key('admin-contact-dispatch-retry')));
    await tester.tap(find.byKey(const Key('admin-contact-dispatch-retry')));
    await tester.pumpAndSettle();
    expect(
      find.text('The server already attempted delivery for this booking.'),
      findsOneWidget,
    );
  });
}
