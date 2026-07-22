import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/driver_trip_contact.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/models/driver_status.dart';
import 'package:frontend/features/driver/pages/driver_booking_detail_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';
import 'package:frontend/features/driver_location/services/driver_location_api_service.dart';
import 'package:frontend/features/driver_settlement/services/driver_settlement_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:geolocator/geolocator.dart';

const _releaseAssignmentButtonLabel = '배정 반납 / คืนงานที่ได้รับมอบหมาย';
const _releaseAssignmentDialogTitle =
    '이 예약의 배정을 반납하시겠습니까?\n(ต้องการคืนงานที่ได้รับมอบหมายสำหรับการจองนี้หรือไม่)';
const _releaseAssignmentDialogCancel = '유지 / คงไว้';
const _releaseReasonScheduleConflict = '일정 충돌 / ตารางงานซ้ำซ้อน';
const _releaseReasonAccident = '사고 / อุบัติเหตุ';

void main() {
  testWidgets('shows standby confirmation and release actions when assigned', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'ACCEPT_BOOKING', 'RELEASE_ASSIGNMENT'],
            releaseAssignmentAvailable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, '운행 준비 확인 / ยืนยันว่าพร้อมปฏิบัติงาน'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, '픽업지 도착 / ถึงจุดรับแล้ว'),
      findsNothing,
    );
  });

  testWidgets(
    'standby confirmation calls accept endpoint and unlocks start route',
    (tester) async {
      final api = _FakeDriverApi(
        detail: _booking(
          status: 'DRIVER_ASSIGNED',
          actions: ['VIEW_DETAILS', 'ACCEPT_BOOKING'],
        ),
      );
      await tester.pumpWidget(_wrap(api));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, '운행 준비 확인 / ยืนยันว่าพร้อมปฏิบัติงาน'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            FilledButton,
            '운행 확정 / ยืนยัน',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.acceptCalls, 1);
      expect(
        find.widgetWithText(
          FilledButton,
          '픽업지로 출발 / ออกเดินทางไปรับลูกค้า',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows loading state', (tester) async {
    final completer = Completer<DriverBooking>();
    await tester.pumpWidget(
      _wrap(_FakeDriverApi(detailFuture: completer.future)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_booking());
    await tester.pumpAndSettle();
  });

  testWidgets('shows controlled backend error state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
          actionError: const DriverApiException(
            'Invalid status transition',
            errorCode: 'INVALID_STATUS_TRANSITION',
            statusCode: 409,
          ),
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
  });

  testWidgets('hides raw database error on end trip failure', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'PICKED_UP', actions: ['END_TRIP']),
          actionError: const DriverApiException(
            "Data truncated for column 'status' at row 1",
            errorCode: 'INTERNAL_SERVER_ERROR',
            statusCode: 500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .widgetWithText(FilledButton, '운행 종료 / ยืนยันจบงาน')
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '운행 종료 / จบการเดินทาง'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Data truncated for column 'status' at row 1"),
      findsNothing,
    );
    expect(
      find.textContaining('We could not complete the trip'),
      findsOneWidget,
    );
  });

  testWidgets('shows mark arrived after on route', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '픽업지 도착 / ถึงจุดรับแล้ว'),
      findsOneWidget,
    );
  });

  testWidgets('shows customer onboard after arrival', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ARRIVED',
            actions: ['MARK_PICKED_UP'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '고객 탑승 확인 / รับลูกค้าขึ้นรถแล้ว'),
      findsOneWidget,
    );
  });

  testWidgets('customer onboard action requires confirmation before API call', (
    tester,
  ) async {
    final api = _FakeDriverApi(
      detail: _booking(status: 'DRIVER_ARRIVED', actions: ['MARK_PICKED_UP']),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, '고객 탑승 확인 / รับลูกค้าขึ้นรถแล้ว'),
    );
    await tester.pumpAndSettle();

    expect(api.markPickedUpCalls, 0);
    expect(find.text('고객이 차량에 탑승했습니까?'), findsOneWidget);
    expect(find.text('탑승 확인 후 운행이 시작됩니다.'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '탑승 확인 / ยืนยันขึ้นรถ'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.markPickedUpCalls, 1);
    expect(api.detailCalls, greaterThan(1));
    expect(
      find.widgetWithText(FilledButton, '운행 종료 / ยืนยันจบงาน'),
      findsOneWidget,
    );
  });

  testWidgets('shows end trip after pickup', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'PICKED_UP', actions: ['END_TRIP']),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '운행 종료 / ยืนยันจบงาน'),
      findsOneWidget,
    );
  });

  testWidgets('detail direct entry starts location after online status loads', (
    tester,
  ) async {
    final locationApi = _FakeLocationApi();
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']),
          online: true,
        ),
        showStatusControl: true,
        locationApi: locationApi,
      ),
    );

    await tester.pump();
    expect(locationApi.calls, 0);
    await tester.pumpAndSettle();

    expect(locationApi.calls, 1);
  });

  testWidgets('detail direct entry does not start location while offline', (
    tester,
  ) async {
    final locationApi = _FakeLocationApi();
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ARRIVED',
            actions: ['MARK_PICKED_UP'],
          ),
          online: false,
        ),
        showStatusControl: true,
        locationApi: locationApi,
      ),
    );

    await tester.pumpAndSettle();

    expect(locationApi.calls, 0);
  });

  testWidgets(
    'detail direct entry does not start location for assigned status',
    (tester) async {
      final locationApi = _FakeLocationApi();
      await tester.pumpWidget(
        _wrap(
          _FakeDriverApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['VIEW_DETAILS', 'START_ON_ROUTE'],
            ),
            online: true,
          ),
          showStatusControl: true,
          locationApi: locationApi,
        ),
      );

      await tester.pumpAndSettle();

      expect(locationApi.calls, 0);
    },
  );

  testWidgets('detail direct entry does not start location after trip ends', (
    tester,
  ) async {
    final locationApi = _FakeLocationApi();
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'SETTLEMENT_PENDING', actions: []),
          online: true,
        ),
        showStatusControl: true,
        locationApi: locationApi,
      ),
    );

    await tester.pumpAndSettle();

    expect(locationApi.calls, 0);
  });

  testWidgets(
    'end trip dialog shows known customer payment amount and settlement popup',
    (tester) async {
      final api = _FakeDriverApi(
        detail: _booking(status: 'PICKED_UP', actions: ['END_TRIP']),
      );
      final settlementApi = _FakeSettlementApi();
      await tester.pumpWidget(_wrap(api, settlementApi: settlementApi));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          '운행 종료 / ยืนยันจบงาน',
        ),
      );
      await tester.pumpAndSettle();

      expect(api.endTripCalls, 0);
      expect(find.text('고객을 목적지에 내려드렸습니까?'), findsOneWidget);
      expect(find.text('THB 1,300'), findsWidgets);
      expect(find.textContaining('기사에게 현장 결제'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '운행 종료 / จบการเดินทาง'),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.endTripCalls, 1);
      expect(api.detailCalls, greaterThan(1));
      expect(settlementApi.detailCalls, greaterThanOrEqualTo(1));
      expect(find.text('정산이 필요합니다'), findsOneWidget);
      expect(find.text('THB 200'), findsOneWidget);
      expect(find.text('SCB'), findsOneWidget);
      expect(find.text('T-Ride'), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
      expect(find.text('0999999999'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('송금증 업로드'), findsOneWidget);
      expect(find.textContaining('신규 배차'), findsOneWidget);
    },
  );

  testWidgets('hides primary action for completed booking', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'COMPLETED', actions: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.widgetWithText(
        FilledButton,
        '픽업지로 출발 / ออกเดินทางไปรับลูกค้า',
      ),
      findsNothing,
    );
    expect(
      find.widgetWithText(FilledButton, '픽업지 도착 / ถึงจุดรับแล้ว'),
      findsNothing,
    );
    expect(
      find.widgetWithText(FilledButton, '운행 종료 / ยืนยันจบงาน'),
      findsNothing,
    );
  });

  testWidgets(
    'detail shows route map, name board, and total fare without commission',
    (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _wrap(
          _FakeDriverApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['VIEW_DETAILS', 'START_ON_ROUTE'],
              nameSignRequested: true,
              withCoordinates: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driverRouteMap')), findsOneWidget);
      expect(find.text('THB 1,300'), findsWidgets);
      expect(find.textContaining('네임보드 서비스'), findsOneWidget);
      expect(find.textContaining('회사에 납부할 수수료'), findsNothing);
      expect(find.textContaining('기사 예상 수입'), findsNothing);
    },
  );

  testWidgets('detail shows pickup and destination names with full addresses', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS'],
            pickupLocation: const DriverBookingLocation(
              name: 'Suvarnabhumi Airport',
              address: '999 Moo 1 Nong Prue, Bang Phli, Samut Prakan 10540',
              latitude: 13.69,
              longitude: 100.7501,
              placeId: 'google-bkk',
            ),
            destinationLocation: const DriverBookingLocation(
              name: 'Hilton Pattaya',
              address: '333/101 Beach Road, Pattaya City, Chon Buri 20260',
              latitude: 12.934,
              longitude: 100.883,
              placeId: 'google-hilton-pattaya',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(
      find.text('999 Moo 1 Nong Prue, Bang Phli, Samut Prakan 10540'),
      findsOneWidget,
    );
    expect(find.text('Hilton Pattaya'), findsOneWidget);
    expect(
      find.text('333/101 Beach Road, Pattaya City, Chon Buri 20260'),
      findsOneWidget,
    );
    expect(find.textContaining('Google Maps'), findsWidgets);
  });

  testWidgets(
    'detail map still renders when only one endpoint has coordinates',
    (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _wrap(
          _FakeDriverApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              actions: ['VIEW_DETAILS'],
              originLatitude: 13.69,
              originLongitude: 100.7501,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driverRouteMap')), findsOneWidget);
    },
  );

  testWidgets('detail avoids duplicate location name and address text', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS'],
            pickupLocation: const DriverBookingLocation(
              name: 'BKK Airport',
              address: 'BKK Airport',
            ),
            destinationLocation: const DriverBookingLocation(
              address: 'Pattaya Hotel',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BKK — Suvarnabhumi Airport'), findsOneWidget);
    expect(find.text('Pattaya Hotel'), findsOneWidget);
    // Avoid showing the same raw "BKK Airport" label twice.
    expect(find.text('BKK Airport'), findsNothing);
  });

  test('driver maps URL uses coordinates when available', () {
    final uri = DriverTripContact.googleMapsUriForLocation(
      const DriverBookingLocation(
        name: 'Suvarnabhumi Airport',
        address: '999 Moo 1 Nong Prue',
        latitude: 13.69,
        longitude: 100.7501,
        placeId: 'ignored-when-coordinates-exist',
      ),
    );

    expect(uri, isNotNull);
    expect(uri!.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['query'], '13.69,100.7501');
    expect(uri.queryParameters.containsKey('query_place_id'), false);
  });

  test('driver maps URL falls back to place query and place id', () {
    final uri = DriverTripContact.googleMapsUriForLocation(
      const DriverBookingLocation(
        name: 'Hilton Pattaya',
        address: '333/101 Beach Road',
        placeId: 'google-hilton-pattaya',
      ),
    );

    expect(uri, isNotNull);
    expect(uri!.queryParameters['query'], 'Hilton Pattaya 333/101 Beach Road');
    expect(uri.queryParameters['query_place_id'], 'google-hilton-pattaya');
  });

  test('driver maps URL rejects ambiguous Bangkok city-only queries', () {
    expect(
      DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(address: 'Bangkok, Thailand'),
      ),
      isNull,
    );
  });

  test('driver maps URL rejects empty or invalid locations', () {
    expect(
      DriverTripContact.googleMapsUriForLocation(
        const DriverBookingLocation(latitude: 120, longitude: 200),
      ),
      isNull,
    );
    expect(
      DriverTripContact.googleMapsUriForLocation(const DriverBookingLocation()),
      isNull,
    );
  });

  testWidgets('airport booking shows airport arrival standby reference', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'ACCEPT_BOOKING'],
            standbyReferenceTimeType: 'AIRPORT_ARRIVAL',
            standbyReferenceTime: '2026-07-01 10:15:00',
            standbyAllowedAt: '2026-07-01T02:15:00.000Z',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('항공편 도착 기준 시각'), findsOneWidget);
    expect(find.text('2026-07-01 10:15:00'), findsOneWidget);
    expect(find.text('2026-07-01T02:15:00.000Z'), findsOneWidget);
  });

  testWidgets('general booking shows vehicle departure standby reference', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'ACCEPT_BOOKING'],
            standbyReferenceTimeType: 'VEHICLE_DEPARTURE',
            standbyReferenceTime: '2026-07-01 09:30:00',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('차량 출발 기준 시각'), findsOneWidget);
    expect(find.text('2026-07-01 09:30:00'), findsWidgets);
  });

  testWidgets('hides primary action for no-show booking', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(status: 'NO_SHOW', actions: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(
        FilledButton,
        '픽업지로 출발 / ออกเดินทางไปรับลูกค้า',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'shows release button when primaryKey is null but release is available',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          _FakeDriverApi(
            detail: _booking(
              status: 'DRIVER_ASSIGNED',
              // No trip primary action → primaryKey is null (standby not open yet).
              actions: ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT'],
              releaseAssignmentAvailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Confirm ready for job'),
        findsNothing,
      );
      expect(
        find.widgetWithText(FilledButton, 'Head to pickup'),
        findsNothing,
      );
    },
  );

  testWidgets('release action confirms, calls API once, and pops detail', (
    tester,
  ) async {
    final api = _FakeDriverApi(
      detail: _booking(
        status: 'DRIVER_ASSIGNED',
        actions: ['VIEW_DETAILS', 'START_ON_ROUTE', 'RELEASE_ASSIGNMENT'],
        releaseAssignmentAvailable: true,
      ),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
    );
    await tester.pumpAndSettle();

    expect(find.text(_releaseAssignmentDialogTitle), findsOneWidget);
    expect(
      find.textContaining('고객 예약은 유지되며'),
      findsOneWidget,
    );

    await _selectReleaseReason(tester, _releaseReasonScheduleConflict);
    await tester.tap(find.byKey(const ValueKey('driver_release_confirm')));
    await tester.pumpAndSettle();

    expect(api.releaseCalls, 1);
    expect(api.lastReleaseReasonCode, 'SCHEDULE_CONFLICT');
    expect(find.byType(DriverBookingDetailPage), findsNothing);
  });

  testWidgets('release dialog cancel does not call API', (tester) async {
    final api = _FakeDriverApi(
      detail: _booking(
        status: 'DRIVER_ASSIGNED',
        actions: ['VIEW_DETAILS', 'START_ON_ROUTE', 'RELEASE_ASSIGNMENT'],
        releaseAssignmentAvailable: true,
      ),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, _releaseAssignmentDialogCancel));
    await tester.pumpAndSettle();

    expect(api.releaseCalls, 0);
    expect(find.byType(DriverBookingDetailPage), findsOneWidget);
  });

  testWidgets('release failure keeps detail and refreshes stale status', (
    tester,
  ) async {
    final api = _FakeDriverApi(
      detail: _booking(
        status: 'DRIVER_ASSIGNED',
        actions: ['VIEW_DETAILS', 'START_ON_ROUTE', 'RELEASE_ASSIGNMENT'],
        releaseAssignmentAvailable: true,
      ),
      releaseError: const DriverApiException(
        'Booking can only be released before the trip starts',
        errorCode: 'BOOKING_RELEASE_NOT_ALLOWED',
        statusCode: 409,
      ),
    );
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
    );
    await tester.pumpAndSettle();
    await _selectReleaseReason(tester, _releaseReasonAccident);
    await tester.tap(find.byKey(const ValueKey('driver_release_confirm')));
    await tester.pumpAndSettle();

    expect(api.releaseCalls, 1);
    expect(api.detailCalls, greaterThan(1));
    expect(find.byType(DriverBookingDetailPage), findsOneWidget);
    expect(find.textContaining('Booking can only be released'), findsOneWidget);
  });

  testWidgets('release button hidden after driver arrived', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ARRIVED',
            actions: ['MARK_PICKED_UP'],
            releaseAssignmentAvailable: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
      findsNothing,
    );
  });

  testWidgets('emergency-only release shows emergency hint', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'START_ON_ROUTE', 'RELEASE_ASSIGNMENT'],
            releaseAssignmentAvailable: false,
            releaseAssignmentEmergencyOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(OutlinedButton, _releaseAssignmentButtonLabel),
      findsOneWidget,
    );
    expect(
      find.textContaining('픽업까지 2시간 이내'),
      findsWidgets,
    );
  });

  testWidgets('shows backend message on initial load failure', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detailError: const DriverApiException(
            'Booking not found',
            errorCode: 'BOOKING_NOT_FOUND',
            statusCode: 404,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking information could not be found.'), findsOneWidget);
    expect(find.text('다시 시도 / ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('customer cancel reason shows assignment ended guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detailError: const DriverApiException(
            'The customer cancelled the booking.',
            errorCode: 'DRIVER_ASSIGNMENT_RELEASED',
            statusCode: 409,
            details: {
              'reasonCode': 'CUSTOMER_CANCELLED',
              'bookingNumber': 'TX202607010001',
              'bookingStatus': 'CANCELLED',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'The customer cancelled the booking, so your assignment was released automatically.',
      ),
      findsOneWidget,
    );
    expect(find.text('OK'), findsOneWidget);
    expect(find.textContaining('Booking not found'), findsNothing);
    expect(find.textContaining('콜을 찾을 수 없습니다'), findsNothing);
  });

  testWidgets('driver booking detail does not show customer message action', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeDriverApi(
          detail: _booking(
            status: 'DRIVER_ASSIGNED',
            actions: ['VIEW_DETAILS', 'START_ON_ROUTE'],
            phone: '+66812345678',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('고객에게 전화'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('고객에게 메시지 보내기 / ส่งข้อความหาลูกค้า'), findsNothing);
    expect(find.text('고객에게 전화 / โทรหาลูกค้า'), findsOneWidget);
  });
}

Widget _wrap(
  DriverApiService api, {
  bool showStatusControl = false,
  DriverLocationApiService? locationApi,
  DriverSettlementApiService? settlementApi,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLanguages
        .map((code) => Locale(code))
        .toList(),
    localizationsDelegates: [
      AppLocalizationsDelegate(locale.languageCode),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    ),
    home: DriverBookingDetailPage(
      bookingNumber: 'TX202607010001',
      api: api,
      showStatusControl: showStatusControl,
      locationApi: locationApi,
      settlementApi: settlementApi,
      positionProvider: () async => _position(),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

DriverBooking _booking({
  String status = 'DRIVER_ASSIGNED',
  List<String> actions = const ['VIEW_DETAILS'],
  String? phone = '+66123456789',
  String assignmentStatus = 'ASSIGNED',
  String? standbyReferenceTimeType,
  String? standbyReferenceTime,
  String? standbyAllowedAt,
  bool nameSignRequested = false,
  bool withCoordinates = false,
  DriverBookingLocation? pickupLocation,
  DriverBookingLocation? destinationLocation,
  double? originLatitude,
  double? originLongitude,
  double? destinationLatitude,
  double? destinationLongitude,
  bool releaseAssignmentAvailable = false,
  bool releaseAssignmentEmergencyOnly = false,
}) {
  return DriverBooking(
    bookingNumber: 'TX202607010001',
    status: status,
    assignmentStatus: assignmentStatus,
    scheduledPickupAt: '2026-07-01 09:30:00',
    standbyReferenceTimeType: standbyReferenceTimeType ?? 'VEHICLE_DEPARTURE',
    standbyReferenceTime: standbyReferenceTime ?? '2026-07-01 09:30:00',
    standbyAllowedAt: standbyAllowedAt ?? '2026-07-01T01:30:00.000Z',
    serviceTypeName: 'Airport Pickup',
    pickupDate: '2026-07-01',
    pickupTime: '09:30',
    origin: 'BKK Airport',
    destination: 'Pattaya Hotel',
    pickupLocation: pickupLocation,
    destinationLocation: destinationLocation,
    originLatitude: originLatitude ?? (withCoordinates ? 13.69 : null),
    originLongitude: originLongitude ?? (withCoordinates ? 100.7501 : null),
    destinationLatitude:
        destinationLatitude ?? (withCoordinates ? 12.9236 : null),
    destinationLongitude:
        destinationLongitude ?? (withCoordinates ? 100.8825 : null),
    passengerCount: 2,
    vehicleTypeName: 'SUV',
    customerDisplayName: 'Kim',
    customerPhone: phone,
    nameSignRequested: nameSignRequested,
    customerPaymentAmount: 1300,
    customerPaymentCurrency: 'THB',
    customerPaymentMethod: 'PAY_DRIVER_AT_DESTINATION',
    companyCommissionAmount: 200,
    companyCommissionCurrency: 'THB',
    driverExpectedIncomeAmount: 1100,
    driverExpectedIncomeCurrency: 'THB',
    currency: 'THB',
    paymentMethodLabel: 'PAY_DRIVER_AT_DESTINATION',
    allowedActions: actions,
    releaseAssignmentAvailable: releaseAssignmentAvailable,
    releaseAssignmentEmergencyOnly: releaseAssignmentEmergencyOnly,
  );
}

Future<void> _selectReleaseReason(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('driver_release_reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _FakeDriverApi extends DriverApiService {
  _FakeDriverApi({
    DriverBooking? detail,
    Future<DriverBooking>? detailFuture,
    this.detailError,
    this.actionError,
    this.releaseError,
    this.online = true,
  }) {
    _current = detail ?? _booking();
    if (detailFuture != null) {
      _detailFuture = detailFuture;
    }
  }

  late DriverBooking _current;
  Future<DriverBooking>? _detailFuture;
  final Exception? detailError;
  final Exception? actionError;
  final Exception? releaseError;
  bool online;
  int detailCalls = 0;
  int releaseCalls = 0;
  String? lastReleaseReasonCode;
  String? lastReleaseReasonDetail;
  int acceptCalls = 0;
  int markPickedUpCalls = 0;
  int endTripCalls = 0;

  @override
  Future<DriverBooking> getBookingDetail(String bookingNumber) async {
    detailCalls += 1;
    if (detailError != null) throw detailError!;
    if (_detailFuture != null) return _detailFuture!;
    return _current;
  }

  @override
  Future<DriverStatus> getStatus() async {
    await Future<void>.delayed(Duration.zero);
    return DriverStatus(
      driverId: 7,
      active: true,
      online: online,
      status: online ? 'AVAILABLE' : 'OFFLINE',
      hasActiveJob: const {
        'DRIVER_ASSIGNED',
        'ON_ROUTE',
        'DRIVER_ARRIVED',
        'PICKED_UP',
      }.contains(_current.status),
    );
  }

  @override
  Future<Map<String, dynamic>> releaseAssignment(
    String bookingNumber, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    releaseCalls += 1;
    lastReleaseReasonCode = reasonCode;
    lastReleaseReasonDetail = reasonDetail;
    if (releaseError != null) throw releaseError!;
    _current = _booking(status: 'OPEN', actions: []);
    return {
      'bookingNumber': bookingNumber,
      'status': 'OPEN',
      'released': true,
      'reasonCode': reasonCode,
    };
  }

  @override
  Future<DriverBooking> confirmStandby(String bookingNumber) async {
    acceptCalls += 1;
    if (actionError != null) throw actionError!;
    _current = _booking(
      status: 'DRIVER_ASSIGNED',
      actions: ['VIEW_DETAILS', 'START_ON_ROUTE'],
      assignmentStatus: 'ACCEPTED',
    );
    return _current;
  }

  @override
  Future<DriverBooking> startOnRoute(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'ON_ROUTE', actions: ['MARK_ARRIVED']);
    return _current;
  }

  @override
  Future<DriverBooking> markArrived(String bookingNumber) async {
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'DRIVER_ARRIVED', actions: ['MARK_PICKED_UP']);
    return _current;
  }

  @override
  Future<DriverBooking> markPickedUp(String bookingNumber) async {
    markPickedUpCalls += 1;
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'PICKED_UP', actions: ['END_TRIP']);
    return _current;
  }

  @override
  Future<DriverBooking> endTrip(String bookingNumber) async {
    endTripCalls += 1;
    if (actionError != null) throw actionError!;
    _current = _booking(status: 'SETTLEMENT_PENDING', actions: []);
    return _current;
  }

  @override
  Future<DriverBooking> completeTrip(String bookingNumber) async {
    return endTrip(bookingNumber);
  }
}

class _FakeSettlementApi extends DriverSettlementApiService {
  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>> getSettlement(String bookingNumber) async {
    detailCalls += 1;
    return {
      'bookingNumber': bookingNumber,
      'commissionStatus': 'PENDING',
      'companyCommissionAmount': 200,
      'companyCommissionCurrency': 'THB',
      'paymentInstructions': {
        'bankName': 'SCB',
        'accountName': 'T-Ride',
        'accountNumber': '1234567890',
        'promptPayNumber': '0999999999',
        'promptPayQrImageUrl': '/api/v1/settings/assets/promptPayQr?v=test',
      },
    };
  }
}

class _FakeLocationApi extends DriverLocationApiService {
  int calls = 0;

  @override
  Future<void> updateDriverLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? heading,
    double? speedKph,
    DateTime? recordedAt,
  }) async {
    calls += 1;
  }
}

Position _position() => Position(
  latitude: 12.9236,
  longitude: 100.8825,
  timestamp: DateTime.now(),
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 0,
  speed: 10,
  speedAccuracy: 0,
);
