import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/seo/booking_search_metadata.dart';

void main() {
  MaterialPageRoute<void> page(String name) => MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox.shrink(),
  );

  test('Japanese booking search copy identifies Thailand and Pattaya', () {
    final metadata = BookingSearchMetadata.forPage('ja', '/booking');
    expect(metadata?.title, contains('タイ'));
    expect(metadata?.title, contains('パタヤ'));
    expect(metadata?.description, contains('スワンナプーム'));
    expect(metadata?.description, contains('ドンムアン'));
  });

  test('tracking and service query values do not affect search copy', () {
    final metadata = BookingSearchMetadata.forPage(
      'ja',
      '/booking?service=GOLF_TRANSFER&lang=ja&utm_source=facebook',
    );
    expect(
      metadata?.title,
      BookingSearchMetadata.forPage('ja', '/booking')?.title,
    );
  });

  test(
    'other languages and utility/private routes retain existing metadata',
    () {
      for (final language in ['ko', 'en', 'zh', 'ru', 'th']) {
        expect(BookingSearchMetadata.forPage(language, '/booking'), isNull);
      }
      for (final route in [
        '/support',
        '/account',
        '/admin',
        '/booking/lookup',
        '/',
      ]) {
        expect(BookingSearchMetadata.forPage('ja', route), isNull);
      }
    },
  );

  test(
    'language changes apply and restore search copy without changing routes',
    () {
      final changes = <BookingSearchMetadata?>[];
      final observer = BookingSearchMetadataObserver(
        initialPath: '/booking',
        onMetadataChanged: changes.add,
      );
      observer.setLanguage('ja');
      observer.setLanguage('ja');
      expect(changes, hasLength(1));
      expect(changes.last, isNotNull);
      observer.setLanguage('en');
      expect(changes.last, isNull);
      observer.setLanguage('ja');
      expect(changes.last, isNotNull);
    },
  );

  test('navigation away and back restores route-specific metadata', () {
    final changes = <BookingSearchMetadata?>[];
    final observer = BookingSearchMetadataObserver(
      initialPath: '/booking',
      onMetadataChanged: changes.add,
    )..setLanguage('ja');
    final booking = page('/booking');
    final support = page('/support');
    observer.didPush(booking, null);
    observer.didPush(support, booking);
    expect(changes.last, isNull);
    observer.didPop(support, booking);
    expect(changes.last, isNotNull);
    observer.didReplace(newRoute: page('/account'), oldRoute: booking);
    expect(changes.last, isNull);
  });

  test('removing an inactive page does not change current metadata', () {
    final changes = <BookingSearchMetadata?>[];
    final observer = BookingSearchMetadataObserver(
      initialPath: '/booking',
      onMetadataChanged: changes.add,
    )..setLanguage('ja');
    final booking = page('/booking');
    observer.didPush(booking, null);
    final count = changes.length;
    observer.didRemove(page('/support'), null);
    expect(changes, hasLength(count));
    expect(changes.last, isNotNull);
  });

  test('replacing an inactive page does not change current metadata', () {
    final changes = <BookingSearchMetadata?>[];
    final observer = BookingSearchMetadataObserver(
      initialPath: '/booking',
      onMetadataChanged: changes.add,
    )..setLanguage('ja');
    final support = page('/support');
    final booking = page('/booking');
    observer.didPush(support, null);
    observer.didPush(booking, support);
    final count = changes.length;
    observer.didReplace(newRoute: page('/account'), oldRoute: support);
    expect(changes, hasLength(count));
    expect(changes.last, isNotNull);
    observer.didPop(booking, page('/account'));
    expect(changes.last, isNull);
  });
}
