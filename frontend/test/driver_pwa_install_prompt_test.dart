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

  testWidgets(
    'late install event changes preparing button into install action',
    (tester) async {
      final service = _FakePwaInstallService();

      await tester.pumpWidget(_host(service: service));
      await tester.pumpAndSettle();

      expect(find.text('Preparing installation...'), findsWidgets);
      expect(_installNowButton(tester).enabled, isFalse);

      service.markInstallPromptAvailable();
      await tester.pumpAndSettle();

      expect(find.text('Preparing installation...'), findsNothing);
      expect(find.text('Install now'), findsOneWidget);
      expect(_installNowButton(tester).enabled, isTrue);
    },
  );

  testWidgets('already prepared install event enables install immediately', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Preparing installation...'), findsNothing);
    expect(_installNowButton(tester).enabled, isTrue);
  });

  testWidgets('manual guidance appears after waiting for install event', (
    tester,
  ) async {
    final service = _FakePwaInstallService();

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('If the install window does not appear'),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('If the install window does not appear'),
      findsOneWidget,
    );
    expect(_installNowButton(tester).enabled, isFalse);
  });

  testWidgets('prepared install button invokes prompt once', (tester) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();

    expect(service.promptCalls, 1);
    expect(find.text('Install T-Ride Driver'), findsNothing);
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

  testWidgets('in-app browser shows Chrome guidance and skips auto install', (
    tester,
  ) async {
    final service = _FakePwaInstallService(
      canPromptInstallValue: true,
      isInAppBrowserValue: true,
    );

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Install T-Ride Driver'), findsOneWidget);
    expect(find.textContaining('Open this page in Chrome'), findsOneWidget);
    expect(_installNowButton(tester).enabled, isFalse);
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(service.promptCalls, 0);
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

FilledButton _installNowButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton));
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
    this.isInAppBrowserValue = false,
  });

  bool isSupportedValue = true;
  bool isStandaloneValue;
  bool isInstalledValue = false;
  bool canPromptInstallValue;
  bool isIosValue = false;
  bool isInAppBrowserValue;
  PwaInstallResult nextResult = PwaInstallResult.accepted;
  int promptCalls = 0;

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
  bool get isInAppBrowser => isInAppBrowserValue;

  @override
  Future<PwaInstallResult> promptInstall() async {
    promptCalls += 1;
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

  void markInstallPromptAvailable() {
    canPromptInstallValue = true;
    notifyListeners();
  }

  void emitChange() {
    notifyListeners();
  }
}
