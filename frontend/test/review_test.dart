import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/widgets/booking_review_form.dart';
import 'package:frontend/features/booking/utils/review_tags.dart';
import 'package:frontend/features/admin_review/pages/admin_review_queue_page.dart';
import 'package:frontend/features/admin_review/services/admin_review_api_service.dart';
import 'package:frontend/l10n/app_localizations.dart';

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
  List<String>? lastTags;

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
    List<String>? tags,
    String? comment,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    submitCalls += 1;
    lastTags = tags;
    if (submitError != null) throw submitError!;
    return submitResult ?? {
      'eligible': true,
      'submitted': true,
      'rating': rating,
      'tags': tags ?? [],
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

Widget _reviewFormScaffold(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: child,
      ),
    ),
  );
}

void main() {
  test('isValidReviewRating validates range', () {
    expect(isValidReviewRating(1), isTrue);
    expect(isValidReviewRating(5), isTrue);
    expect(isValidReviewRating(0), isFalse);
    expect(isValidReviewRating(6), isFalse);
  });

  test('ReviewTags visibility by rating', () {
    expect(ReviewTags.visibleCodes(1), contains('UNSAFE_DRIVING'));
    expect(ReviewTags.visibleCodes(2), contains('LATE_ARRIVAL'));
    expect(ReviewTags.visibleCodes(4), isNot(contains('LATE_ARRIVAL')));
    expect(ReviewTags.visibleCodes(4), contains('FRIENDLY'));
  });

  test('zh review strings resolve without English fallback', () {
    final zh = AppLocalizations('zh');
    final en = AppLocalizations('en');
    expect(zh.t('review_card_title'), '本次乘车体验如何？');
    expect(zh.t('review_card_subtitle'), '请选择评分');
    expect(zh.t('review_rating_desc_5'), '非常满意');
    expect(zh.t('review_tag_FRIENDLY'), '服务友好');
    expect(zh.t('review_tag_UNSAFE_DRIVING'), '驾驶不安全');
    expect(zh.t('review_submit_button'), '提交评分');
    expect(zh.t('review_success_title'), '感谢您的评价');
    expect(zh.t('review_success_body'), '您的反馈将帮助我们改进服务');
    expect(zh.t('guest_status_guidance_settlement_pending'), contains('请为司机评分'));
    expect(zh.t('status_customer_settlement_pending'), '行程已结束');
    expect(zh.t('review_card_title'), isNot(en.t('review_card_title')));
    expect(zh.t('review_submit_button'), isNot(en.t('review_submit_button')));
  });

  test('ja review strings resolve without English fallback', () {
    final ja = AppLocalizations('ja');
    final en = AppLocalizations('en');
    expect(ja.t('review_card_title'), '今回の乗車はいかがでしたか？');
    expect(ja.t('review_card_subtitle'), '評価を選択してください');
    expect(ja.t('review_rating_desc_3'), '普通');
    expect(ja.t('review_tag_CLEAN_VEHICLE'), '車内が清潔でした');
    expect(ja.t('review_tag_LATE_ARRIVAL'), '到着が遅れました');
    expect(ja.t('review_submit_button'), '評価を送信');
    expect(ja.t('review_success_title'), 'ご評価ありがとうございます');
    expect(ja.t('review_success_body'), 'サービス改善の参考にさせていただきます');
    expect(ja.t('guest_status_guidance_settlement_pending'), contains('ドライバーを評価'));
    expect(ja.t('status_customer_settlement_pending'), '運行終了');
    expect(ja.t('review_card_title'), isNot(en.t('review_card_title')));
    expect(ja.t('review_submit_button'), isNot(en.t('review_submit_button')));
  });

  testWidgets('review form hidden when not eligible', (tester) async {
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {'eligible': false, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('How was your ride?'), findsNothing);
  });

  testWidgets('review form visible when eligible', (tester) async {
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('How was your ride?'), findsOneWidget);
    expect(find.text('Please select a rating.'), findsOneWidget);
  });

  testWidgets('submit disabled until rating selected', (tester) async {
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit rating'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('rating description updates on star tap', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_2')));
    await tester.pump();
    expect(find.text('Dissatisfied'), findsOneWidget);
    expect(find.text('Unsafe driving'), findsOneWidget);
    expect(find.text('Friendly'), findsOneWidget);
  });

  testWidgets('negative tags hidden for high rating', (tester) async {
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    expect(find.text('Unsafe driving'), findsNothing);
    expect(find.text('Friendly'), findsOneWidget);
  });

  testWidgets('successful guest review submission', (tester) async {
    final api = _FakeReviewApi();
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          guestAccessToken: 'guest-token',
          api: api,
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    await tester.tap(find.text('Friendly'));
    await tester.pump();
    await tester.tap(find.text('Submit rating'));
    await tester.pump();
    expect(api.submitCalls, 1);
    expect(api.lastTags, contains('FRIENDLY'));
    expect(find.text('Thank you for your feedback.'), findsOneWidget);
  });

  testWidgets('already submitted state shows comment', (tester) async {
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {
            'eligible': true,
            'submitted': true,
            'rating': 4,
            'tags': ['ON_TIME'],
            'comment': 'Smooth ride',
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Thank you for your feedback.'), findsOneWidget);
    expect(find.text('Smooth ride'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets('already submitted state', (tester) async {
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          initialState: const {
            'eligible': true,
            'submitted': true,
            'rating': 4,
            'tags': ['ON_TIME'],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Thank you for your feedback.'), findsOneWidget);
    expect(find.text('On time'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets('submit failure keeps form state for retry', (tester) async {
    final api = _FakeReviewApi(submitError: const BookingReviewApiException('Network error'));
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          guestAccessToken: 'guest-token',
          api: api,
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    final submit = find.widgetWithText(ElevatedButton, 'Submit rating');
    expect(submit, findsOneWidget);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump();
    expect(api.submitCalls, 1);
    expect(find.text('Network error'), findsOneWidget);
    expect(find.text('Submit rating'), findsOneWidget);
    expect(find.text('Very satisfied'), findsOneWidget);
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
        'tags': ['FRIENDLY'],
      },
    );
    await tester.pumpWidget(
      _reviewFormScaffold(
        BookingReviewForm(
          bookingNumber: 'TX202607010001',
          guestAccessToken: 'guest-token',
          api: api,
          initialState: const {'eligible': true, 'submitted': false},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_rating_5')));
    await tester.pump();
    await tester.tap(find.text('Submit rating'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Thank you for your feedback.'), findsOneWidget);
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
