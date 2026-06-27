import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/driver/models/driver_booking.dart';
import 'package:frontend/features/driver/pages/driver_jobs_page.dart';
import 'package:frontend/features/driver/services/driver_api_service.dart';

void main() {
  testWidgets('driver rating summary shows average and review count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverJobsPage(
          api: _FakeDriverApi(
            ratingSummary: {'averageRating': 4.5, 'reviewCount': 12},
            jobs: _emptyJobs(),
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
        home: DriverJobsPage(
          api: _FakeDriverApi(
            ratingSummary: {'averageRating': null, 'reviewCount': 0},
            jobs: _emptyJobs(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('0 reviews'), findsOneWidget);
  });

  testWidgets('driver rating summary hides card when endpoint fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverJobsPage(
          api: _FakeDriverApi(
            ratingError: const DriverApiException('Rating unavailable'),
            jobs: _emptyJobs(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsNothing);
    expect(find.text('average'), findsNothing);
    expect(find.text('No jobs today'), findsOneWidget);
  });
}

DriverJobsToday _emptyJobs() {
  return const DriverJobsToday(
    date: '2026-07-01',
    items: [],
  );
}

class _FakeDriverApi extends DriverApiService {
  _FakeDriverApi({
    this.ratingSummary,
    this.ratingError,
    required this.jobs,
  });

  final Map<String, dynamic>? ratingSummary;
  final Object? ratingError;
  final DriverJobsToday jobs;

  @override
  Future<Map<String, dynamic>> getRatingSummary() async {
    if (ratingError != null) throw ratingError!;
    return ratingSummary ?? {'averageRating': null, 'reviewCount': 0};
  }

  @override
  Future<DriverJobsToday> getTodayBookings() async => jobs;
}
