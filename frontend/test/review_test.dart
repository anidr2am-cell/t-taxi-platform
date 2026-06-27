import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/features/admin_review/pages/admin_review_queue_page.dart';
import 'package:frontend/features/admin_review/services/admin_review_api_service.dart';

class _FakeReviewApi extends BookingReviewApi {
  _FakeReviewApi({
    this.getState,
    this.submitResult,
    this.submitError,
  });

  final Map<String, dynamic>? Function()? getState;
  final Map<String, dynamic>? submitResult;
  final Object? submitError;
  int submitCalls = 0;

  @override
  Future<Map<String, dynamic>> getReview({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    if (getState != null) return getState!()!;
    return {
      'eligible': true,
      'submitted': false,
    };
  }

  @override
  Future<Map<String, dynamic>> submitReview({
    required String bookingNumber,
    required int rating,
    String? comment,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    submitCalls += 1;
    if (submitError != null) throw submitError!;
    return submitResult ?? {
      'eligible': true,
      'submitted': true,
      'rating': rating,
      'comment': comment,
    };
  }
}

class _FakeAdminReviewApi extends AdminReviewApiService {
  _FakeAdminReviewApi({this.items, this.detail, this.error});

  final List<dynamic>? items;
  final Map<String, dynamic>? detail;
  final Object? error;
  int hideCalls = 0;
  int restoreCalls = 0;

  @override
  Future<Map<String, dynamic>> listReviews({String? status, int? rating, String? search}) async {
    if (error != null) throw error!;
    return {'items': items ?? []};
  }

  @override
  Future<Map<String, dynamic>> getReview(int reviewId) async {
    return detail ?? {'reviewId': reviewId, 'rating': 5, 'moderationStatus': 'VISIBLE', 'comment': 'Nice'};
  }

  @override
  Future<Map<String, dynamic>> hideReview(int reviewId, String reason) async {
    hideCalls += 1;
    return {'reviewId': reviewId, 'moderationStatus': 'HIDDEN', 'hiddenReason': reason};
  }

  @override
  Future<Map<String, dynamic>> restoreReview(int reviewId) async {
    restoreCalls += 1;
    return {'reviewId': reviewId, 'moderationStatus': 'VISIBLE'};
  }
}

void main() {
  test('isValidReviewRating validates range', () {
    expect(isValidReviewRating(1), isTrue);
    expect(isValidReviewRating(5), isTrue);
    expect(isValidReviewRating(0), isFalse);
    expect(isValidReviewRating(6), isFalse);
  });

  testWidgets('review form hidden when not eligible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingReviewForm(
            bookingNumber: 'TX202607010001',
            initialState: const {'eligible': false, 'submitted': false},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Rate your trip'), findsNothing);
  });

  testWidgets('review form visible after COMPLETED', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingReviewForm(
            bookingNumber: 'TX202607010001',
            initialState: const {'eligible': true, 'submitted': false},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Rate your trip'), findsOneWidget);
  });

  testWidgets('successful guest review submission', (tester) async {
    final api = _FakeReviewApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingReviewForm(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: api,
            initialState: const {'eligible': true, 'submitted': false},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    await tester.tap(find.text('Submit review'));
    await tester.pump();
    expect(api.submitCalls, 1);
    expect(find.text('Thank you for your review'), findsOneWidget);
  });

  testWidgets('already submitted state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingReviewForm(
            bookingNumber: 'TX202607010001',
            initialState: const {
              'eligible': true,
              'submitted': true,
              'rating': 4,
              'comment': 'Good',
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Thank you for your review'), findsOneWidget);
    expect(find.text('Rating: 4 / 5'), findsOneWidget);
  });

  testWidgets('retry state on upload failure', (tester) async {
    final api = _FakeReviewApi(submitError: const BookingReviewApiException('Network error'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingReviewForm(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: api,
            initialState: const {'eligible': true, 'submitted': false},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    final submit = find.widgetWithText(ElevatedButton, 'Submit review');
    expect(submit, findsOneWidget);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump();
    expect(api.submitCalls, 1);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('admin review filters render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminReviewQueuePage(
          api: _FakeAdminReviewApi(items: [
            {
              'reviewId': 1,
              'bookingNumber': 'TX202607010001',
              'rating': 5,
              'moderationStatus': 'VISIBLE',
              'customerDisplayName': 'Guest',
              'driver': {'displayName': 'Driver A'},
            },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('TX202607010001 · 5★'), findsOneWidget);
  });

  testWidgets('admin hide flow', (tester) async {
    final api = _FakeAdminReviewApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminReviewDetailPage(reviewId: 1, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Spam');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(api.hideCalls, 1);
  });

  testWidgets('already submitted on REVIEW_ALREADY_SUBMITTED', (tester) async {
    final api = _FakeReviewApi(
      submitError: const BookingReviewApiException(
        'Review already submitted',
        'REVIEW_ALREADY_SUBMITTED',
      ),
      getState: () => {
        'eligible': true,
        'submitted': true,
        'rating': 5,
        'comment': 'Nice',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingReviewForm(
            bookingNumber: 'TX202607010001',
            guestAccessToken: 'guest-token',
            api: api,
            initialState: const {'eligible': true, 'submitted': false},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    await tester.tap(find.text('Submit review'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Thank you for your review'), findsOneWidget);
    expect(api.submitCalls, 1);
  });

  testWidgets('admin restore flow', (tester) async {
    final api = _FakeAdminReviewApi(
      detail: {
        'reviewId': 1,
        'rating': 3,
        'moderationStatus': 'HIDDEN',
        'comment': 'Ok',
        'hiddenReason': 'Spam',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminReviewDetailPage(reviewId: 1, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(api.restoreCalls, 1);
  });
}
