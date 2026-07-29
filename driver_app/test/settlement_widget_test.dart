import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/settlement/data/settlement_models.dart';
import 'package:tride_driver/features/settlement/presentation/receipt_upload_sheet.dart';
import 'package:tride_driver/features/settlement/presentation/settlement_detail_page.dart';
import 'package:tride_driver/features/settlement/presentation/settlement_list_page.dart';

import 'l10n_test_helpers.dart';
import 'test_fakes.dart';

Future<void> pumpSettlementList(
  WidgetTester tester,
  FakeSettlementApi api, {
  Locale locale = const Locale('ko'),
  Size surfaceSize = const Size(360, 640),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    localizedMaterialApp(
      locale: locale,
      home: SettlementListPage(api: api, onUnauthorized: () async {}),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

int _paragraphLineCount(Finder finder, WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    maxLines: paragraph.maxLines,
    textScaler: paragraph.textScaler,
    ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
  )..layout(maxWidth: paragraph.size.width);
  return painter.computeLineMetrics().length;
}

Future<void> pumpSettlementDetail(
  WidgetTester tester,
  FakeSettlementApi api, {
  SettlementReceiptPicker? picker,
}) async {
  await tester.pumpWidget(
    localizedMaterialApp(
      home: SettlementDetailPage(
        api: api,
        bookingNumber: api.detail.bookingNumber,
        onUnauthorized: () async {},
        receiptPicker: picker,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> scrollSettlementDetailTo(
  WidgetTester tester,
  Finder finder,
) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.descendant(
      of: find.byKey(const Key('settlementDetailContent')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('list shows empty state and supports pull refresh', (
    tester,
  ) async {
    final api = FakeSettlementApi()..items = const [];
    await pumpSettlementList(tester, api);

    expect(find.byKey(const Key('settlementListEmpty')), findsOneWidget);
    final initialCount = api.listCount;

    await tester.fling(
      find.byKey(const Key('settlementListEmpty')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(api.listCount, greaterThan(initialCount));
  });

  testWidgets('list card renders status badges with due information', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(bookingNumber: 'TX-DUE', commissionStatus: 'DUE'),
        settlementItem(bookingNumber: 'TX-OVER', commissionStatus: 'OVERDUE'),
        settlementItem(bookingNumber: 'TX-OK', commissionStatus: 'APPROVED'),
      ];
    await pumpSettlementList(tester, api);

    expect(find.byKey(const Key('settlement-TX-DUE')), findsOneWidget);
    expect(find.byKey(const Key('settlementStatus-DUE')), findsOneWidget);
    expect(find.byKey(const Key('settlementStatus-OVERDUE')), findsOneWidget);
    expect(find.byKey(const Key('settlementStatus-APPROVED')), findsOneWidget);
    expect(find.textContaining('TX-DUE'), findsOneWidget);
  });

  testWidgets('list card shows customer payment and driver income on the left', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(
          bookingNumber: 'TX-PAY',
          customerPaymentAmount: 1300,
          companyCommissionAmount: 200,
          driverExpectedIncomeAmount: 1100,
        ),
      ];
    await pumpSettlementList(tester, api);

    expect(find.text('고객 결제액'), findsOneWidget);
    expect(find.text('기사 수입'), findsOneWidget);
    expect(find.text('수수료'), findsOneWidget);
    expect(find.text('THB 1,300'), findsOneWidget);
    expect(find.text('THB 1,100'), findsOneWidget);
    expect(find.text('THB 200'), findsOneWidget);
    expect(find.byKey(const Key('settlementNameSignNote-TX-PAY')), findsNothing);
  });

  testWidgets('list card shows name sign note when amount is positive', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(
          bookingNumber: 'TX-SIGN',
          customerPaymentAmount: 1300,
          companyCommissionAmount: 200,
          driverExpectedIncomeAmount: 1000,
          nameSignAmount: 100,
        ),
      ];
    await pumpSettlementList(tester, api);

    expect(find.text('THB 1,000'), findsOneWidget);
    expect(find.text('(피켓 비용 -100바트 포함)'), findsOneWidget);
    expect(find.byKey(const Key('settlementNameSignNote-TX-SIGN')), findsOneWidget);
  });

  testWidgets('list card hides name sign note when amount is absent or zero', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(bookingNumber: 'TX-NONE', nameSignAmount: null),
        settlementItem(bookingNumber: 'TX-ZERO', nameSignAmount: 0),
      ];
    await pumpSettlementList(tester, api);

    expect(find.textContaining('피켓 비용'), findsNothing);
  });

  testWidgets('list card keeps due date and status chip', (tester) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(
          bookingNumber: 'TX-DUE-DATE',
          commissionStatus: 'DUE',
          dueAt: '2026-07-30T23:59:00.000+07:00',
        ),
      ];
    await pumpSettlementList(tester, api);

    expect(find.byKey(const Key('settlementStatus-DUE')), findsOneWidget);
    expect(find.textContaining('마감: 2026-07-30T23:59:00.000+07:00'), findsOneWidget);
  });

  testWidgets('list card shows fallback when payment amounts are missing', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(
          bookingNumber: 'TX-NULL',
          customerPaymentAmount: null,
          companyCommissionAmount: null,
          driverExpectedIncomeAmount: null,
        ),
      ];
    await pumpSettlementList(tester, api);

    expect(find.text('금액 정보 없음'), findsNWidgets(3));
  });

  testWidgets(
    'list card Thai labels wrap horizontally without one character per line',
    (tester) async {
      final api = FakeSettlementApi()
        ..items = [
          settlementItem(
            bookingNumber: 'TX-TH',
            customerPaymentAmount: 1300,
            companyCommissionAmount: 200,
            driverExpectedIncomeAmount: 1100,
            commissionStatus: 'DUE',
            dueAt: '2026-07-30T23:59:00.000+07:00',
          ),
        ];
      await pumpSettlementList(tester, api, locale: const Locale('th'));

      expect(find.text('ยอดที่ลูกค้าจ่าย'), findsOneWidget);
      expect(find.text('รายได้คนขับ'), findsOneWidget);
      expect(find.text('ค่าคอมมิชชัน'), findsOneWidget);

      final customerLabel = find.text('ยอดที่ลูกค้าจ่าย');
      expect(
        _paragraphLineCount(customerLabel, tester),
        inInclusiveRange(1, 2),
      );

      final commissionLabel = find.text('ค่าคอมมิชชัน');
      expect(
        _paragraphLineCount(commissionLabel, tester),
        inInclusiveRange(1, 2),
      );
    },
  );

  testWidgets('list card Korean labels remain readable after layout change', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(
          bookingNumber: 'TX-KO',
          customerPaymentAmount: 1300,
          companyCommissionAmount: 200,
          driverExpectedIncomeAmount: 1100,
        ),
      ];
    await pumpSettlementList(tester, api);

    expect(find.text('고객 결제액'), findsOneWidget);
    expect(find.text('기사 수입'), findsOneWidget);
    expect(find.text('수수료'), findsOneWidget);
    expect(_paragraphLineCount(find.text('고객 결제액'), tester), 1);
    expect(_paragraphLineCount(find.text('수수료'), tester), 1);
  });

  testWidgets('list card survives narrow width with longest Thai labels', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..items = [
        settlementItem(
          bookingNumber: 'TX-NARROW',
          customerPaymentAmount: 9999999,
          companyCommissionAmount: 9999999,
          driverExpectedIncomeAmount: 9999999,
          nameSignAmount: 100,
          commissionStatus: 'RECEIPT_SUBMITTED',
          dueAt: '2026-07-30T23:59:00.000+07:00',
        ),
      ];
    await pumpSettlementList(
      tester,
      api,
      locale: const Locale('th'),
      surfaceSize: const Size(320, 640),
    );

    expect(find.byKey(const Key('settlement-TX-NARROW')), findsOneWidget);
    expect(find.text('ยอดที่ลูกค้าจ่าย'), findsOneWidget);
    expect(find.text('ค่าคอมมิชชัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail shows blocked banner, rejection reason, and upload CTA', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..detail = settlementItem(
        commissionStatus: 'REJECTED',
        blocksNewCalls: true,
        rejectionReason: 'Receipt is unreadable',
        paymentInstructions: const {
          'bankName': 'Kasikorn',
          'accountName': 'T-Ride Co.',
          'accountNumber': '123-4-56789-0',
        },
      );
    expect(api.detail.paymentInstructions.bankName, 'Kasikorn');
    await pumpSettlementDetail(tester, api);

    expect(find.byKey(const Key('settlementBlockingBanner')), findsOneWidget);
    expect(find.text('Receipt is unreadable'), findsOneWidget);
    expect(
      find.byKey(
        const Key('settlementPaymentInstructions'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await scrollSettlementDetailTo(
      tester,
      find.byKey(const Key('uploadReceiptButton')),
    );
  });

  testWidgets('detail hides upload CTA for approved settlement', (
    tester,
  ) async {
    final api = FakeSettlementApi()
      ..detail = settlementItem(commissionStatus: 'APPROVED');
    await pumpSettlementDetail(tester, api);

    expect(find.byKey(const Key('uploadReceiptButton')), findsNothing);
    expect(find.byKey(const Key('resubmitReceiptButton')), findsNothing);
    expect(find.byKey(const Key('settlementNoAction')), findsOneWidget);
  });

  testWidgets('receipt upload success refreshes detail and receipt preview', (
    tester,
  ) async {
    final api = FakeSettlementApi();
    await pumpSettlementDetail(
      tester,
      api,
      picker: () async =>
          const SettlementUploadFile(filename: 'receipt.jpg', bytes: [1, 2]),
    );

    await scrollSettlementDetailTo(
      tester,
      find.byKey(const Key('uploadReceiptButton')),
    );
    await tester.tap(find.byKey(const Key('uploadReceiptButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pickSettlementReceipt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submitSettlementReceipt')));
    await tester.pumpAndSettle();

    expect(api.uploadCount, 1);
    expect(api.uploadedBookingNumber, api.detail.bookingNumber);
    expect(find.byKey(const Key('resubmitReceiptButton')), findsOneWidget);
    expect(api.downloadCount, greaterThan(0));
  });

  for (final code in [
    'VALIDATION_ERROR',
    'INVALID_FILE_TYPE',
    'FILE_TOO_LARGE',
    'SETTLEMENT_NOT_FOUND',
    'RECEIPT_ALREADY_APPROVED',
  ]) {
    testWidgets('receipt upload shows Korean guidance for $code', (
      tester,
    ) async {
      final api = FakeSettlementApi()
        ..uploadError = ApiException(
          code == 'RECEIPT_ALREADY_APPROVED'
              ? ApiFailureKind.receiptAlreadyApproved
              : ApiFailureKind.validation,
          errorCode: code,
        );
      await pumpSettlementDetail(
        tester,
        api,
        picker: () async =>
            const SettlementUploadFile(filename: 'receipt.pdf', bytes: [1]),
      );

      await scrollSettlementDetailTo(
        tester,
        find.byKey(const Key('uploadReceiptButton')),
      );
      await tester.tap(find.byKey(const Key('uploadReceiptButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pickSettlementReceipt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submitSettlementReceipt')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receiptUploadError')), findsOneWidget);
    });
  }
}
