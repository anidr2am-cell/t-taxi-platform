import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/pwa/driver_pwa_install_prompt.dart';
import 'package:frontend/core/pwa/pwa_install_service.dart';

void main() {
  testWidgets('standalone driver page does not show install prompt', (
    tester,
  ) async {
    final service = _FakePwaInstallService(isStandaloneValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Install T-Ride Driver'), findsNothing);
  });

  testWidgets('driver login page shows install prompt before installation', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Install T-Ride Driver'), findsOneWidget);
    expect(find.text('Install now'), findsOneWidget);
  });

  testWidgets('later dismisses the prompt for the current page session', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Install T-Ride Driver'), findsNothing);
    service.emitChange();
    await tester.pumpAndSettle();
    expect(find.text('Install T-Ride Driver'), findsNothing);
  });

  testWidgets(
    'customer and admin pages without host do not show install prompt',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('customer'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Install T-Ride Driver'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('admin'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Install T-Ride Driver'), findsNothing);
    },
  );

  testWidgets('installed event closes an open prompt', (tester) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    expect(find.text('Install T-Ride Driver'), findsOneWidget);

    service.markInstalled();
    await tester.pumpAndSettle();

    expect(find.text('Install T-Ride Driver'), findsNothing);
  });

  testWidgets('unavailable install API shows manual guidance', (tester) async {
    final service = _FakePwaInstallService(canPromptInstallValue: false);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Install T-Ride Driver'), findsOneWidget);
    expect(
      find.textContaining('If the install window does not appear'),
      findsOneWidget,
    );
  });

  testWidgets('Thai copy is available for the driver install prompt', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(
      _host(service: service, locale: const Locale('th')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsOneWidget);
    expect(find.text('ติดตั้งตอนนี้'), findsOneWidget);
  });
}

Widget _host({
  required PwaInstallService service,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ko'), Locale('th')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: DriverPwaInstallPromptHost(
        service: service,
        child: const Text('driver login'),
      ),
    ),
  );
}

class _FakePwaInstallService extends PwaInstallService {
  _FakePwaInstallService({
    this.isStandaloneValue = false,
    this.canPromptInstallValue = false,
  });

  bool isSupportedValue = true;
  bool isStandaloneValue;
  bool isInstalledValue = false;
  bool canPromptInstallValue;
  bool isIosValue = false;
  PwaInstallResult nextResult = PwaInstallResult.accepted;

  @override
  bool get isSupported => isSupportedValue;

  @override
  bool get isStandalone => isStandaloneValue;

  @override
  bool get isInstalled => isInstalledValue;

  @override
  bool get canPromptInstall => canPromptInstallValue;

  @override
  bool get isIos => isIosValue;

  @override
  Future<PwaInstallResult> promptInstall() async {
    if (nextResult == PwaInstallResult.accepted) {
      isInstalledValue = true;
      canPromptInstallValue = false;
      notifyListeners();
    }
    return nextResult;
  }

  void markInstalled() {
    isInstalledValue = true;
    canPromptInstallValue = false;
    notifyListeners();
  }

  void emitChange() {
    notifyListeners();
  }
}
