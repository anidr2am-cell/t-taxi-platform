import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/guest_booking_lookup_inquiry_banner.dart';
import 'package:frontend/features/platform_settings/services/platform_settings_api_service.dart';

class _FakeGuestLookupInquiryApi extends PlatformSettingsApiService {
  _FakeGuestLookupInquiryApi(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<Map<String, dynamic>> getGuestLookupInquiry() async => payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides banner when enabled is false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestBookingLookupInquiryBanner(
            api: _FakeGuestLookupInquiryApi({
              'enabled': false,
              'message': '문의해 주세요',
              'channels': [
                {
                  'code': 'LINE',
                  'displayName': 'LINE',
                  'addUrl': 'https://line.me/R/ti/p/@example',
                  'enabled': true,
                },
              ],
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guest_lookup_inquiry_banner')), findsNothing);
  });

  testWidgets('shows message and enabled channel icons when enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestBookingLookupInquiryBanner(
            api: _FakeGuestLookupInquiryApi({
              'enabled': true,
              'message': '관리자에게 문의하세요',
              'channels': [
                {
                  'code': 'KAKAO',
                  'displayName': 'KakaoTalk',
                  'addUrl': 'https://open.kakao.com/o/s/example',
                  'enabled': true,
                },
                {
                  'code': 'LINE',
                  'displayName': 'LINE',
                  'addUrl': 'https://line.me/R/ti/p/@example',
                  'enabled': true,
                },
              ],
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guest_lookup_inquiry_banner')), findsOneWidget);
    expect(find.text('관리자에게 문의하세요'), findsOneWidget);
    expect(find.byKey(const Key('guest_lookup_inquiry_channel_KAKAO')), findsOneWidget);
    expect(find.byKey(const Key('guest_lookup_inquiry_channel_LINE')), findsOneWidget);
  });

  testWidgets('channel icon tap launches addUrl', (tester) async {
    Uri? launchedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestBookingLookupInquiryBanner(
            api: _FakeGuestLookupInquiryApi({
              'enabled': true,
              'message': 'LINE 문의',
              'channels': [
                {
                  'code': 'LINE',
                  'displayName': 'LINE',
                  'addUrl': 'https://line.me/R/ti/p/@example',
                  'enabled': true,
                },
              ],
            }),
            launchUrlOverride: (uri) async {
              launchedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guest_lookup_inquiry_channel_LINE')));
    await tester.pumpAndSettle();

    expect(launchedUri, Uri.parse('https://line.me/R/ti/p/@example'));
  });
}
