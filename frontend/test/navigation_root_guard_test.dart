import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/booking_provider.dart';
import 'package:frontend/screens/admin/admin_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin root does not pop to customer route', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleState(),
        child: MaterialApp(
          home: const _CustomerPlaceholder(),
          routes: {'/admin': (_) => const AdminScreen(initialTab: 6)},
        ),
      ),
    );

    await tester.tap(find.text('Open admin'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text('Customer root'), findsNothing);
  });
}

class _CustomerPlaceholder extends StatelessWidget {
  const _CustomerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Customer root'),
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/admin'),
            child: const Text('Open admin'),
          ),
        ],
      ),
    );
  }
}
