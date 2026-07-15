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

    await tester.pumpWidget(
      _host(service: service, locale: const Locale('ko')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsNothing);
  });

  testWidgets('driver login page shows install prompt before installation', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsOneWidget);
    expect(find.text('ติดตั้งตอนนี้'), findsOneWidget);
  });

  testWidgets('driver install prompt stays Thai when locale is Korean', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(
      _host(service: service, locale: const Locale('ko')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsOneWidget);
    expect(find.text('ติดตั้งตอนนี้'), findsOneWidget);
    expect(find.text('T-Ride 기사 앱 설치'), findsNothing);
  });

  testWidgets('driver install prompt stays Thai when locale is English', (
    tester,
  ) async {
    final service = _FakePwaInstallService();

    await tester.pumpWidget(
      _host(service: service, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('กำลังเตรียมการติดตั้ง...'), findsWidgets);
    expect(find.text('Preparing installation...'), findsNothing);
  });

  testWidgets(
    'late install event changes preparing button into install action',
    (tester) async {
      final service = _FakePwaInstallService();

      await tester.pumpWidget(_host(service: service));
      await tester.pumpAndSettle();

      expect(find.text('กำลังเตรียมการติดตั้ง...'), findsWidgets);
      expect(_installNowButton(tester).enabled, isFalse);

      service.markInstallPromptAvailable();
      await tester.pumpAndSettle();

      expect(find.text('กำลังเตรียมการติดตั้ง...'), findsNothing);
      expect(find.text('ติดตั้งตอนนี้'), findsOneWidget);
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
    expect(find.textContaining('หากหน้าต่างติดตั้งไม่แสดง'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.textContaining('หากหน้าต่างติดตั้งไม่แสดง'), findsOneWidget);
    expect(_installNowButton(tester).enabled, isFalse);
  });

  testWidgets('prepared install button invokes prompt once', (tester) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ติดตั้งตอนนี้'));
    await tester.pumpAndSettle();

    expect(service.promptCalls, 1);
    expect(find.text('ติดตั้งสำเร็จแล้ว'), findsOneWidget);
    expect(service.closeWindowCalls, 1);
  });

  testWidgets('accepted install keeps current driver route and avoids root', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_hostWithRoutes(service: service));
    await tester.pumpAndSettle();
    expect(find.text('driver route'), findsOneWidget);
    expect(find.text('customer root'), findsNothing);

    await tester.tap(find.text('ติดตั้งตอนนี้'));
    await tester.pumpAndSettle();

    expect(find.text('driver route'), findsOneWidget);
    expect(find.text('customer root'), findsNothing);
    expect(find.text('ติดตั้งสำเร็จแล้ว'), findsOneWidget);
  });

  testWidgets(
    'accepted and appinstalled events show completion once and close once',
    (tester) async {
      final service = _FakePwaInstallService(canPromptInstallValue: true);

      await tester.pumpWidget(_host(service: service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ติดตั้งตอนนี้'));
      service.markInstalled();
      await tester.pumpAndSettle();

      expect(find.text('ติดตั้งสำเร็จแล้ว'), findsOneWidget);
      expect(service.promptCalls, 1);
      expect(service.closeWindowCalls, 1);
    },
  );

  testWidgets('manual close guidance appears when browser stays open', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ติดตั้งตอนนี้'));
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งสำเร็จแล้ว'), findsOneWidget);
    expect(find.textContaining('กรุณาปิดเบราว์เซอร์นี้'), findsOneWidget);
    expect(find.text('ปิดเบราว์เซอร์'), findsOneWidget);
  });

  testWidgets('dismissed install does not navigate to customer root', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true)
      ..nextResult = PwaInstallResult.dismissed;

    await tester.pumpWidget(_hostWithRoutes(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ติดตั้งตอนนี้'));
    await tester.pumpAndSettle();

    expect(find.text('driver route'), findsOneWidget);
    expect(find.text('customer root'), findsNothing);
  });

  testWidgets('later dismisses the prompt for the current page session', (
    tester,
  ) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ไว้ภายหลัง'));
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsNothing);
    service.emitChange();
    await tester.pumpAndSettle();
    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsNothing);
  });

  testWidgets(
    'customer and admin pages without host do not show install prompt',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('customer'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('ติดตั้งแอป T-Ride Driver'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('admin'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('ติดตั้งแอป T-Ride Driver'), findsNothing);
    },
  );

  testWidgets('installed event shows one completion prompt', (tester) async {
    final service = _FakePwaInstallService(canPromptInstallValue: true);

    await tester.pumpWidget(_host(service: service));
    await tester.pumpAndSettle();
    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsOneWidget);

    service.markInstalled();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('ติดตั้งสำเร็จแล้ว'), findsOneWidget);
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

    expect(find.text('ติดตั้งแอป T-Ride Driver'), findsOneWidget);
    expect(
      find.textContaining('กรุณาเปิดลิงก์นี้ด้วย Google Chrome'),
      findsOneWidget,
    );
    expect(_installNowButton(tester).enabled, isFalse);
    await tester.tap(find.text('ติดตั้งตอนนี้'));
    await tester.pumpAndSettle();
    expect(service.promptCalls, 0);
  });

  testWidgets('Thai copy is used for the driver install prompt', (
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

Widget _hostWithRoutes({required PwaInstallService service}) {
  return MaterialApp(
    initialRoute: '/driver',
    routes: {
      '/': (_) => const Scaffold(body: Text('customer root')),
      '/driver': (_) => Scaffold(
        body: DriverPwaInstallPromptHost(
          service: service,
          child: const Text('driver route'),
        ),
      ),
    },
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
  int closeWindowCalls = 0;

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

  @override
  Future<bool> tryCloseWindow() async {
    closeWindowCalls += 1;
    return false;
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
