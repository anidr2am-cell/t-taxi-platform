import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/admin_dashboard/pages/admin_statistics_page.dart';
import 'package:frontend/features/admin_dispatch/services/admin_dispatch_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _StatisticsApi extends AdminDispatchApiService {
  @override
  Future<Map<String, dynamic>> getStatistics(String from, String to) async {
    const usage = {'bookings': 2, 'passengers': 4};
    return {
      'from': from,
      'to': to,
      'timezone': 'Asia/Bangkok',
      'totals': usage,
      'daily': [
        {'key': '2026-10-31', ...usage},
      ],
      'monthly': [
        {'key': '2026-10', ...usage},
      ],
      'countries': [
        {'key': '+82', ...usage},
      ],
      'flights': [
        {'key': '7C2551', ...usage},
      ],
      'services': [
        {'key': 'AIRPORT_PICKUP', ...usage},
      ],
    };
  }
}

void main() {
  testWidgets('Switches daily and monthly statistics at 375 px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: AdminStatisticsPage(api: _StatisticsApi())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('통계'), findsOneWidget);
    expect(find.text('2026-10-31'), findsOneWidget);
    await tester.tap(find.text('월별'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10'), findsOneWidget);
    expect(find.text('2026-10-31'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Statistics labels are available in every admin language', () {
    for (final language in ['ko', 'en', 'th', 'ja', 'zh']) {
      final l10n = AppLocalizations(language);
      for (final key in [
        'admin_statistics',
        'admin_stats_scope',
        'admin_stats_country_note',
        'admin_stats_monthly',
        'admin_stats_nameSign',
      ]) {
        expect(l10n.t(key), isNot(key), reason: language);
      }
    }
  });
}
