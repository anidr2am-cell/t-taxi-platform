import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/models/contact_channel.dart';
import 'package:frontend/features/booking/services/booking_contact_connection_service.dart';
import 'package:frontend/features/booking/widgets/booking_messenger_handoff_section.dart';
import 'package:frontend/l10n/app_localizations.dart';

class _FakeContactService extends BookingContactConnectionService {
  _FakeContactService(this.channels) : super(baseUrl: 'http://test');

  final List<ContactChannel> channels;

  @override
  Future<List<ContactChannel>> getPublicChannels() async => channels;
}

void main() {
  const channels = [
    ContactChannel(
      code: 'LINE',
      displayName: 'LINE',
      addUrl: 'https://line.me/example',
    ),
    ContactChannel(
      code: 'KAKAO',
      displayName: 'KakaoTalk',
      addUrl: 'https://open.kakao.com/example',
    ),
    ContactChannel(
      code: 'WHATSAPP',
      displayName: 'WhatsApp',
      phoneNumber: '66815693445',
    ),
    ContactChannel(code: 'WECHAT', displayName: 'WeChat', accountId: 'trider'),
    ContactChannel(code: 'EMAIL', displayName: 'Email'),
  ];

  test('handoff channels exclude email and keep Kakao first in Korean', () {
    final result = bookingHandoffChannels(channels, 'ko');
    expect(result.map((channel) => channel.code), [
      'KAKAO',
      'LINE',
      'WHATSAPP',
    ]);
  });

  test('handoff message contains the booking number without customer data', () {
    expect(
      bookingMessengerHandoffMessage('TX202610020001'),
      'T-Rider booking TX202610020001',
    );
  });

  testWidgets('shows required messengers, assignment milestones and no email', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: [
          AppLocalizationsDelegate('ko'),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ko')],
        home: Scaffold(
          body: BookingMessengerHandoffSection(
            bookingNumber: 'TX202610020001',
            service: _FakeContactService(channels),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('차량 사진과 기사 배정 알림을 어디로 받을까요?'), findsOneWidget);
    expect(find.text('예약 접수 완료'), findsOneWidget);
    expect(find.text('차량 배정 중'), findsOneWidget);
    expect(find.byKey(const Key('booking_handoff_kakao')), findsOneWidget);
    expect(find.byKey(const Key('booking_handoff_line')), findsOneWidget);
    expect(find.byKey(const Key('booking_handoff_whatsapp')), findsOneWidget);
    expect(find.textContaining('Email'), findsNothing);
    expect(find.textContaining('이메일'), findsNothing);
  });
}
