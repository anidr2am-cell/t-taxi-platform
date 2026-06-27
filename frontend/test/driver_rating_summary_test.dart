import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/pages/driver_profile_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';

void main() {
  testWidgets('driver rating summary shows average and review count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverProfilePage(
          api: _FakeDriverApi(
            ratingSummary: {'averageRating': 4.5, 'reviewCount': 12},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4.5 average'), findsOneWidget);
    expect(find.text('12 reviews'), findsOneWidget);
    expect(find.text('Great service'), findsNothing);
  });

  testWidgets('driver rating summary shows no-ratings state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverProfilePage(
          api: _FakeDriverApi(
            ratingSummary: {'averageRating': null, 'reviewCount': 0},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('0 reviews'), findsOneWidget);
  });

  testWidgets('driver rating summary shows error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverProfilePage(
          api: _FakeDriverApi(
            ratingError: const DriverApiException('Rating unavailable'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load rating'), findsOneWidget);
    expect(find.text('average'), findsNothing);
  });
}

class _FakeDriverApi extends DriverApiService {
  _FakeDriverApi({
    this.ratingSummary,
    this.ratingError,
  });

  final Map<String, dynamic>? ratingSummary;
  final Object? ratingError;

  @override
  Future<Map<String, dynamic>> getRatingSummary() async {
    if (ratingError != null) throw ratingError!;
    return ratingSummary ?? {'averageRating': null, 'reviewCount': 0};
  }
}
