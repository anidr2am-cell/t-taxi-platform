import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/features/booking/pages/booking_contact_connect_page.dart';

void main() {
  testWidgets('direct messenger URL retains booking query on initial entry', (
    tester,
  ) async {
    const name =
        '/booking/contact-connect?bookingNumber=TX202610250001&lang=en';
    final route = buildBookingEntryRoute(const RouteSettings(name: name));
    expect(route, isA<MaterialPageRoute<void>>());
    BookingContactConnectRouteLoader? loader;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            loader =
                (route! as MaterialPageRoute<void>).builder(context)
                    as BookingContactConnectRouteLoader;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(loader!.uri!.queryParameters['bookingNumber'], 'TX202610250001');
    expect(loader!.uri!.queryParameters['lang'], 'en');
  });

  test('other routes still use their existing routing', () {
    expect(
      buildBookingEntryRoute(const RouteSettings(name: '/admin?lang=en')),
      isNull,
    );
    expect(
      buildBookingEntryRoute(
        const RouteSettings(name: '/booking?service=AIRPORT_DROPOFF&lang=en'),
      ),
      isNotNull,
    );
  });
}
