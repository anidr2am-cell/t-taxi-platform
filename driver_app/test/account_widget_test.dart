import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/features/account/data/account_models.dart';
import 'package:tride_driver/features/account/presentation/account_page.dart';
import 'package:tride_driver/features/account/presentation/profile_edit_page.dart';
import 'package:tride_driver/features/account/presentation/vehicle_add_page.dart';
import 'package:tride_driver/features/account/presentation/vehicle_list_page.dart';

import 'test_fakes.dart';

void main() {
  testWidgets(
    'account shows no-review state and reuses dispatch online toggle',
    (tester) async {
      final account = FakeAccountApi()
        ..rating = const RatingSummary(averageRating: null, reviewCount: 0);
      final dispatch = FakeDispatchReader();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountPage(
            accountApi: account,
            dispatchRepository: dispatch,
            onUnauthorized: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('아직 리뷰 없음'), findsOneWidget);
      await tester.tap(find.byKey(const Key('accountOnlineToggle')));
      await tester.pumpAndSettle();
      expect(dispatch.onlineCount, 1);
    },
  );

  testWidgets('profile save sends changed fields only', (tester) async {
    _useTallView(tester);
    final api = FakeAccountApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(api: api, initialProfile: api.profile),
      ),
    );
    await tester.enterText(find.byKey(const Key('profileName')), 'New Name');
    await tester.ensureVisible(find.byKey(const Key('saveProfile')));
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    expect(api.updateCount, 1);
    expect(api.lastChanges, {'name': 'New Name'});
  });

  testWidgets('profile replaces avatar and vehicle photo', (tester) async {
    _useTallView(tester);
    final api = FakeAccountApi();
    var pickCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          api: api,
          initialProfile: api.profile,
          pickImage: () async => AccountUploadFile(
            filename: pickCount++ == 0 ? 'avatar.jpg' : 'vehicle.webp',
            bytes: const [1, 2],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('replaceAvatar')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('replaceVehiclePhoto')));
    await tester.tap(find.byKey(const Key('replaceVehiclePhoto')));
    await tester.pumpAndSettle();

    expect(api.avatarCount, 1);
    expect(api.vehiclePhotoCount, 1);
  });

  testWidgets('profile explains unavailable vehicle photo approval', (
    tester,
  ) async {
    _useTallView(tester);
    final api = FakeAccountApi()
      ..profile = driverProfile(vehicle: null)
      ..vehiclePhotoError = const ApiException(
        ApiFailureKind.validation,
        statusCode: 409,
        errorCode: 'VALIDATION_ERROR',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          api: api,
          initialProfile: api.profile,
          pickImage: () async =>
              const AccountUploadFile(filename: 'vehicle.jpg', bytes: [1]),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const Key('vehiclePhotoUnavailableNotice')),
    );
    expect(
      find.byKey(const Key('vehiclePhotoUnavailableNotice')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('replaceVehiclePhoto')));
    await tester.tap(find.byKey(const Key('replaceVehiclePhoto')));
    await tester.pumpAndSettle();
    expect(find.text('승인된 기사 지원서가 없어 차량 사진을 변경할 수 없습니다.'), findsOneWidget);
  });

  testWidgets('vehicle list shows empty state', (tester) async {
    final api = FakeAccountApi()..vehicles = const [];
    await tester.pumpWidget(
      MaterialApp(
        home: VehicleListPage(api: api, onUnauthorized: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vehicleEmpty')), findsOneWidget);
  });

  testWidgets('vehicle list shows status badges and rejection reason', (
    tester,
  ) async {
    _useTallView(tester);
    final api = FakeAccountApi()
      ..vehicles = [
        driverVehicle(id: 1, approvalStatus: 'PENDING', isPrimary: false),
        driverVehicle(id: 2),
        driverVehicle(
          id: 3,
          approvalStatus: 'REJECTED',
          isPrimary: false,
          rejectionReason: '서류 불명확',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: VehicleListPage(api: api, onUnauthorized: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vehicleStatus-PENDING')), findsOneWidget);
    expect(find.byKey(const Key('vehicleStatus-APPROVED')), findsOneWidget);
    expect(find.byKey(const Key('vehicleStatus-REJECTED')), findsOneWidget);
    expect(find.text('거절 사유: 서류 불명확'), findsOneWidget);
  });

  testWidgets('vehicle add stays disabled until exact file constraints pass', (
    tester,
  ) async {
    final api = FakeAccountApi();
    final documents = <AccountUploadFile>[
      const AccountUploadFile(filename: 'insurance.pdf', bytes: [1]),
      const AccountUploadFile(filename: 'registration.jpg', bytes: [1]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: VehicleAddPage(
          api: api,
          pickPhotos: (_) async => const [
            AccountUploadFile(filename: 'one.jpg', bytes: [1]),
            AccountUploadFile(filename: 'two.jpg', bytes: [1]),
            AccountUploadFile(filename: 'three.jpg', bytes: [1]),
          ],
          pickDocument: () async => documents.removeAt(0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vehiclePlate')), 'NEW-123');

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('submitVehicle')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submitVehicle')))
          .onPressed,
      isNull,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('pickVehiclePhotos')));
    await tester.tap(find.byKey(const Key('pickVehiclePhotos')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('insuranceSelector')),
        matching: find.text('선택'),
      ),
    );
    await tester.pump();
    final registrationButton = find.descendant(
      of: find.byKey(const Key('registrationSelector')),
      matching: find.text('선택'),
    );
    await tester.ensureVisible(registrationButton);
    await tester.tap(registrationButton);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submitVehicle')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('vehicle add succeeds with pending guidance', (tester) async {
    _useTallView(tester);
    final api = FakeAccountApi();
    await _readyVehicleForm(tester, api);
    await tester.ensureVisible(find.byKey(const Key('submitVehicle')));
    await tester.tap(find.byKey(const Key('submitVehicle')));
    await tester.pumpAndSettle();

    expect(api.createVehicleCount, 1);
    expect(api.lastVehicleRequest?.vehiclePhotos, hasLength(3));
  });

  testWidgets('vehicle add explains duplicate plate', (tester) async {
    _useTallView(tester);
    final api = FakeAccountApi()
      ..vehicleCreateError = const ApiException(
        ApiFailureKind.vehiclePlateAlreadyRegistered,
        statusCode: 409,
        errorCode: 'VEHICLE_PLATE_ALREADY_REGISTERED',
      );
    await _readyVehicleForm(tester, api);
    await tester.ensureVisible(find.byKey(const Key('submitVehicle')));
    await tester.tap(find.byKey(const Key('submitVehicle')));
    await tester.pumpAndSettle();

    expect(find.text('이미 등록된 차량 번호입니다.'), findsOneWidget);
  });
}

Future<void> _readyVehicleForm(WidgetTester tester, FakeAccountApi api) async {
  final documents = <AccountUploadFile>[
    const AccountUploadFile(filename: 'insurance.pdf', bytes: [1]),
    const AccountUploadFile(filename: 'registration.pdf', bytes: [1]),
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: VehicleAddPage(
        api: api,
        pickPhotos: (_) async => const [
          AccountUploadFile(filename: 'one.jpg', bytes: [1]),
          AccountUploadFile(filename: 'two.png', bytes: [1]),
          AccountUploadFile(filename: 'three.webp', bytes: [1]),
        ],
        pickDocument: () async => documents.removeAt(0),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('vehiclePlate')), 'NEW-123');
  await tester.tap(find.byKey(const Key('pickVehiclePhotos')));
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('insuranceSelector')),
      matching: find.text('선택'),
    ),
  );
  await tester.pump();
  final registrationButton = find.descendant(
    of: find.byKey(const Key('registrationSelector')),
    matching: find.text('선택'),
  );
  await tester.ensureVisible(registrationButton);
  await tester.tap(registrationButton);
  await tester.pumpAndSettle();
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
