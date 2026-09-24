import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_booking_detail_page.dart';
import 'package:frontend/features/admin_dispatch/pages/admin_manual_booking_create_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/theme/app_theme.dart';

class _FakeDetailApi extends AdminDispatchApiService {
  const _FakeDetailApi();

  static Map<String, dynamic> stringAmountFixture(String bookingNumber) {
    return {
      'bookingNumber': bookingNumber,
      'status': 'OPEN',
      'manualCallActions': {'canEdit': true, 'canCancel': false},
      'scheduledPickupAt': '2026-09-24T03:00:00.000Z',
      'allowedActions': ['ASSIGN_DRIVER', 'VIEW_DETAILS'],
      'primaryCta': 'ASSIGN_DRIVER',
      'operations': {'primaryCta': 'ASSIGN_DRIVER'},
      'route': {
        'origin': {'address': '999 Virtual Airport Rd', 'name': 'Suvarnabhumi QA'},
        'destination': {'address': 'Virtual Pattaya Beach', 'name': 'Pattaya QA'},
      },
      'customer': {'name': 'QA Guest Kim', 'phone': '+66800000001'},
      'pricing': {
        'paymentMethod': 'PAY_DRIVER',
        'paymentStatus': 'UNPAID',
        'totalAmount': 1200,
        'currency': 'THB',
        'chargeItems': [
          {
            'chargeType': 'OTHER',
            'description': 'Admin manual payout',
            'quantity': 1,
            'unitPrice': '850',
            'amount': '850',
          },
        ],
      },
      'flight': {'flightNumber': 'TG123', 'airportIata': 'BKK'},
      'vehicle': {'typeCode': 'VAN', 'typeName': 'Van', 'count': 1},
      'passengers': {'adults': 2, 'children': 1, 'infants': 0},
      'luggage': {
        'carriers20Inch': 1,
        'carriers24InchPlus': 2,
        'golfBags': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getBookingDetail(String bookingNumber) async {
    return stringAmountFixture(bookingNumber);
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
  Future<List<dynamic>> listDrivers({
    bool? archived,
    String? bookingNumber,
  }) async {
    return [
      {
        'driverId': 101,
        'displayName': 'QA Active No Conflict',
        'phone': '+66801000001',
        'eligibilityState': 'AVAILABLE',
        'activeAssignmentCount': 1,
        'assignmentEligible': true,
        'pickupTimeConflict': false,
      },
    ];
  }
}

void main() {
  testWidgets('manual edit route supplies Material text styling and a back button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('ko'),
        localizationsDelegates: [
          AppLocalizationsDelegate('ko'),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ko')],
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202609240003',
          api: const _FakeDetailApi(),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    // The form contains animated controls; wait for the route and fixture load,
    // then assert the loaded content instead of waiting for all animations.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final edit = find.byType(AdminManualBookingCreatePage);
    expect(edit, findsOneWidget);
    final editContext = tester.element(edit);
    expect(Scaffold.maybeOf(editContext), isNotNull);
    final titleContext = tester.element(
      find.descendant(of: edit, matching: find.text('관리자 콜 수정')),
    );
    expect(DefaultTextStyle.of(titleContext).style.decoration,
        isNot(TextDecoration.underline));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AdminBookingDetailPage), findsOneWidget);
    expect(edit, findsNothing);
  });

  testWidgets('AdminBookingDetailPage renders string charge amounts and assign CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('ko'),
        localizationsDelegates: [
          AppLocalizationsDelegate('ko'),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ko')],
        home: AdminBookingDetailPage(
          bookingNumber: 'TX202609240003',
          api: const _FakeDetailApi(),
          onChanged: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('TX202609240003'), findsWidgets);
    expect(find.textContaining('850 THB'), findsOneWidget);

    final assignButton = find.text('Assign driver');
    await tester.scrollUntilVisible(
      assignButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(assignButton, findsOneWidget);

    await tester.tap(assignButton);
    await tester.pumpAndSettle();

    expect(find.text('QA Active No Conflict'), findsOneWidget);
  });
}
