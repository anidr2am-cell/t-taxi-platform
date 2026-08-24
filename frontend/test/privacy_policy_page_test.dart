import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/legal/pages/privacy_policy_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child, {double width = 375, Locale locale = const Locale('ko')}) {
  return ChangeNotifierProvider(
    create: (_) => LocaleState()..setLanguage(locale.languageCode),
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: [
        AppLocalizationsDelegate(locale.languageCode),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: child,
      ),
    ),
  );
}

Future<void> _goldenAtSection(
  WidgetTester tester, {
  required double width,
  required String sectionMarker,
  required String goldenPath,
}) async {
  await tester.pumpWidget(
    _wrap(
      PrivacyPolicyPage(initialMarkdown: policyMarkdown),
      width: width,
    ),
  );
  await tester.pumpAndSettle();

  await tester.scrollUntilVisible(
    find.textContaining(sectionMarker),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(goldenPath),
  );
}

late String policyMarkdown;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    policyMarkdown = File('assets/legal/privacy_policy.md').readAsStringSync();
  });

  group('PrivacyPolicyPage', () {
    test('asset markdown matches docs source', () {
      final docsFile = File('../docs/privacy_policy.md');
      final assetFile = File('assets/legal/privacy_policy.md');
      expect(docsFile.existsSync(), isTrue);
      expect(assetFile.existsSync(), isTrue);
      expect(assetFile.readAsStringSync(), docsFile.readAsStringSync());
    });

    testWidgets('renders reviewed policy markdown formatting', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PrivacyPolicyPage(initialMarkdown: policyMarkdown),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('T-Rider(티라이더) 개인정보처리방침'), findsOneWidget);
      expect(find.textContaining('시행일자'), findsOneWidget);
      expect(find.textContaining(r'\---'), findsNothing);

      await tester.scrollUntilVisible(
        find.textContaining('예약 서비스 제공'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('예약 서비스 제공'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Gabia'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('수탁업체'), findsOneWidget);
      expect(find.textContaining('Gabia'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Edward'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Edward'), findsOneWidget);
    });

    testWidgets('375px layout golden', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PrivacyPolicyPage(initialMarkdown: policyMarkdown),
          width: 375,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/privacy_policy_375.png'),
      );
    });

    testWidgets('1100px layout golden', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PrivacyPolicyPage(initialMarkdown: policyMarkdown),
          width: 1100,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/privacy_policy_1100.png'),
      );
    });

    testWidgets('375px section 4 third-party table golden', (tester) async {
      await _goldenAtSection(
        tester,
        width: 375,
        sectionMarker: '제공받는 자',
        goldenPath: 'goldens/privacy_policy_375_section4.png',
      );
    });

    testWidgets('375px section 5 consignment table golden', (tester) async {
      await _goldenAtSection(
        tester,
        width: 375,
        sectionMarker: '수탁업체',
        goldenPath: 'goldens/privacy_policy_375_section5.png',
      );
    });

    testWidgets('375px section 10 privacy officer table golden', (tester) async {
      await _goldenAtSection(
        tester,
        width: 375,
        sectionMarker: '개인정보 보호책임자',
        goldenPath: 'goldens/privacy_policy_375_section10.png',
      );
    });

    testWidgets('1100px section 4 third-party table golden', (tester) async {
      await _goldenAtSection(
        tester,
        width: 1100,
        sectionMarker: '제공받는 자',
        goldenPath: 'goldens/privacy_policy_1100_section4.png',
      );
    });

    testWidgets('1100px section 5 consignment table golden', (tester) async {
      await _goldenAtSection(
        tester,
        width: 1100,
        sectionMarker: '수탁업체',
        goldenPath: 'goldens/privacy_policy_1100_section5.png',
      );
    });

    testWidgets('1100px section 10 privacy officer table golden', (tester) async {
      await _goldenAtSection(
        tester,
        width: 1100,
        sectionMarker: '개인정보 보호책임자',
        goldenPath: 'goldens/privacy_policy_1100_section10.png',
      );
    });
  });
}
