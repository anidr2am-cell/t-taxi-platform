import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart';
import 'package:frontend/providers/booking_provider.dart';

void main() {
  testWidgets('App loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleState()),
          ChangeNotifierProvider(create: (_) => BookingState()),
        ],
        child: const TTaxiApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TTaxi'), findsOneWidget);
  });
}
