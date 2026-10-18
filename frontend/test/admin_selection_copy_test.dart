import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin/widgets/admin_copy_button.dart';
import 'package:frontend/features/admin/widgets/admin_selection_area.dart';
import 'package:frontend/l10n/app_localizations.dart';

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: [
    AppLocalizationsDelegate('ko'),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('ko')],
  home: AdminSelectionArea(child: Scaffold(body: child)),
);

void main() {
  testWidgets('copy succeeds or fails with localized feedback', (tester) async {
    String? copied;
    await tester.pumpWidget(
      app(
        AdminCopyButton(
          text: 'QA_ID',
          label: 'ID',
          copyText: (value) async {
            copied = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pumpAndSettle();
    expect(copied, 'QA_ID');
    expect(find.text('복사했습니다'), findsOneWidget);
    await tester.pumpWidget(
      app(
        AdminCopyButton(
          text: 'QA_ID',
          label: 'ID',
          copyText: (_) async => throw PlatformException(code: 'denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pumpAndSettle();
    expect(
      find.text(AppLocalizations('ko').t('admin_copy_failed')),
      findsOneWidget,
    );
  });

  testWidgets('empty contact has no copy action', (tester) async {
    await tester.pumpWidget(app(const AdminCopyRow(label: '전화번호', value: '')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
    expect(find.text('-'), findsOneWidget);
  });

  testWidgets(
    'mouse drag selects text, Ctrl+C copies, fields and buttons still work',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            clipboard = (call.arguments as Map)['text'] as String?;
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var tapped = false;
      await tester.pumpWidget(
        app(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('QA_SELECTABLE_BOOKING', key: Key('selectable')),
              TextField(controller: controller),
              TextButton(
                onPressed: () => tapped = true,
                child: const Text('OPEN_DETAIL'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const Key('selectable')));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.centerLeft);
      await mouse.down(rect.centerLeft + const Offset(1, 0));
      await mouse.moveTo(rect.centerRight + const Offset(1, 0));
      await mouse.up();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(clipboard, contains('QA_SELECTABLE_BOOKING'));
      await tester.enterText(find.byType(TextField), 'editable');
      expect(controller.text, 'editable');
      await tester.tap(find.text('OPEN_DETAIL'));
      expect(tapped, isTrue);
    },
  );

  test('copy feedback has all five translations', () {
    for (final language in AppLocalizations.supportedLanguages) {
      for (final key in [
        'admin_copy_action',
        'admin_copy_success',
        'admin_copy_failed',
      ]) {
        expect(AppLocalizations(language).t(key), isNot(key));
      }
    }
  });
}
