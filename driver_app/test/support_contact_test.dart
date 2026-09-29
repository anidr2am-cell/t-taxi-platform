import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tride_driver/config/app_config.dart';
import 'package:tride_driver/config/app_environment.dart';
import 'package:tride_driver/core/network/api_client.dart';
import 'package:tride_driver/features/support/data/support_contact_api.dart';
import 'package:tride_driver/features/support/presentation/driver_support_page.dart';

import 'l10n_test_helpers.dart';

class _FakeSupportApi implements SupportContactDataSource {
  _FakeSupportApi(this.url);

  final Uri? url;

  @override
  Future<Uri?> getAdministratorLineUrl() async => url;
}

void main() {
  test('loads the enabled LINE public contact URL', () async {
    final api = SupportContactApi(
      client: ApiClient(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/bookings/contact-channels/public');
          return http.Response(
            '{"success":true,"data":{"channels":['
            '{"code":"LINE","enabled":true,"addUrl":"https://lin.ee/55A9phq"}'
            ']}}',
            200,
          );
        }),
      ),
    );

    expect(
      await api.getAdministratorLineUrl(),
      Uri.parse('https://lin.ee/55A9phq'),
    );
  });

  test('rejects unsafe LINE contact URLs', () async {
    final api = SupportContactApi(
      client: ApiClient(
        config: AppConfig.forEnvironment(AppEnvironment.stg),
        httpClient: MockClient(
          (_) async => http.Response(
            '{"success":true,"data":{"channels":['
            '{"code":"LINE","enabled":true,"addUrl":"javascript:alert(1)"}'
            ']}}',
            200,
          ),
        ),
      ),
    );

    expect(await api.getAdministratorLineUrl(), isNull);
  });

  testWidgets('opens administrator LINE from the support page', (tester) async {
    Uri? opened;
    await pumpLocalizedWidget(
      tester,
      home: DriverSupportPage(
        api: _FakeSupportApi(Uri.parse('https://lin.ee/55A9phq')),
        launchExternal: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('openAdministratorLine')));
    await tester.pumpAndSettle();

    expect(opened, Uri.parse('https://lin.ee/55A9phq'));
  });
}
