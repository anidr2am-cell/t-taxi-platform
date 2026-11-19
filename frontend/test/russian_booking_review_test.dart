import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/features/booking/utils/customer_notification_text.dart';
import 'package:frontend/features/booking/utils/pickup_time_format.dart';
import 'package:frontend/features/booking/utils/flight_time_format.dart';
import 'package:frontend/features/booking/widgets/pickup_time_picker_sheet.dart';
import 'package:frontend/features/booking/widgets/booking_progress_header.dart';

Widget app(String locale, Widget home) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.customerSupportedLanguages
      .map(Locale.new)
      .toList(),
  localizationsDelegates: [
    AppLocalizationsDelegate(locale),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: home),
);

void main() {
  test(
    'reviewed Russian copy is explicit, neutral and preserves placeholders',
    () {
      final l = AppLocalizations('ru');
      final expected = {
        'cx_notice_DRIVER_REASSIGNED':
            'Водитель заменён\nДля вашей поездки назначен другой водитель.',
        'flight_departure_date_help':
            'Выберите дату вылета, указанную в билете, по местному времени аэропорта отправления. Дата подачи определяется по дате прилёта в Таиланд.',
        'pricing_distance_surcharge': 'Доплата за дополнительное расстояние',
        'customer_payment_unknown': 'Уточните способ оплаты',
        'booking_cancel_confirm_irreversible':
            'После отмены восстановить бронирование нельзя.',
        'booking_messenger_handoff_channel': 'Получать уведомления в {channel}',
        'cx_capacity_no_large':
            'Сумки для гольфа: {g}. Места для больших чемоданов не остаётся.',
        'airport_meeting_notify_button': 'Сообщить о готовности к посадке',
      };
      for (final entry in expected.entries) expect(l.t(entry.key), entry.value);
      expect(l.t('wizard_step_vehicle_title'), 'Автомобиль');
      expect(l.t('wizard_step_vehicle_short'), 'Авто');
    },
  );

  for (final locale in AppLocalizations.customerSupportedLanguages) {
    test(
      'old and new reassignment notices use the customer perspective: $locale',
      () {
        final l = AppLocalizations(locale);
        for (final source in [
          ['Booking reassigned', 'You have been assigned to a new booking.'],
          AppLocalizations('en').t('cx_notice_DRIVER_REASSIGNED').split('\n'),
        ]) {
          final n = {
            'notificationType': 'DRIVER_REASSIGNED',
            'title': source[0],
            'body': '${source[1]} (TX202610170001)',
          };
          expect(
            customerNotificationText(l, n, 'title'),
            l.t('cx_notice_DRIVER_REASSIGNED').split('\n')[0],
          );
          expect(
            customerNotificationText(l, n, 'body'),
            '${l.t('cx_notice_DRIVER_REASSIGNED').split('\n')[1]} (TX202610170001)',
          );
        }
        final custom = {
          'notificationType': 'DRIVER_REASSIGNED',
          'body':
              'You have been assigned to a new booking. Please call support.',
        };
        expect(customerNotificationText(l, custom, 'body'), custom['body']);
      },
    );
  }

  test(
    '24-hour display keeps Bangkok conversion and legacy parsing unchanged',
    () {
      for (final hour in [0, 12, 13, 23]) {
        expect(
          PickupTimeFormat.formatDisplay(
            hour24: hour,
            minute: 16,
            amLabel: 'AM',
            pmLabel: 'PM',
            use24Hour: true,
          ),
          '${hour.toString().padLeft(2, '0')}:16',
        );
      }
      expect(
        FlightTimeFormat.formatBangkokDisplay(
          '2026-11-10T16:40:00Z',
          amLabel: 'AM',
          pmLabel: 'PM',
          use24Hour: true,
        ),
        '2026-11-10 23:40',
      );
      expect(
        PickupTimeFormat.parseManualInput(
          '02:00 오후',
          amLabel: '오전',
          pmLabel: '오후',
        ),
        (hour24: 14, minute: 0),
      );
    },
  );

  for (final hour in [0, 12, 23]) {
    testWidgets('Russian picker keeps $hour:16 when confirmed at 375px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ({int hour24, int minute})? result;
      await tester.pumpWidget(
        app(
          'ru',
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PickupTimePickerSheet.show(
                  context,
                  initialHour24: hour,
                  initialMinute: 16,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '${hour.toString().padLeft(2, '0')}:16');
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      final ok = MaterialLocalizations.of(
        tester.element(find.byType(TextField)),
      ).okButtonLabel;
      await tester.tap(find.text(ok));
      await tester.pumpAndSettle();
      expect(result, (hour24: hour, minute: 16));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Russian manual input updates both wheels and returned 24-hour value',
    (tester) async {
      ({int hour24, int minute})? result;
      await tester.pumpWidget(
        app(
          'ru',
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PickupTimePickerSheet.show(
                  context,
                  initialHour24: 1,
                  initialMinute: 16,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '14:35');
      await tester.tap(
        find.text(AppLocalizations('ru').t('pickup_time_apply_manual')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '14:35',
      );
      final ok = MaterialLocalizations.of(
        tester.element(find.byType(TextField)),
      ).okButtonLabel;
      await tester.tap(find.text(ok));
      await tester.pumpAndSettle();
      expect(result, (hour24: 14, minute: 35));
    },
  );

  for (final locale in AppLocalizations.supportedLanguages) {
    testWidgets('legacy AM/PM picker is preserved: $locale', (tester) async {
      await tester.pumpWidget(
        app(
          locale,
          const PickupTimePickerSheet(initialHour24: 13, initialMinute: 16),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations(locale);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '01:16 ${l.t('pickup_time_pm')}',
      );
      expect(find.text(l.t('pickup_time_am')), findsOneWidget);
      expect(find.text(l.t('pickup_time_pm')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [375.0, 720.0, 1440.0]) {
    testWidgets('Russian progress label fits at $width', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 812);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        app('ru', const BookingProgressHeader(currentStep: 2)),
      );
      await tester.pumpAndSettle();
      expect(find.text('3/5 Автомобиль'), findsOneWidget);
      if (width >= 720) {
        final render = tester.renderObject<RenderParagraph>(find.text('Авто'));
        expect(
          render.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
          ),
          hasLength(1),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
