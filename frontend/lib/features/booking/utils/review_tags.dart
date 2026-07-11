/// Stable review tag codes shared with backend reviewTags.js
class ReviewTags {
  ReviewTags._();

  static const positiveCodes = [
    'FRIENDLY',
    'SAFE_DRIVING',
    'CLEAN_VEHICLE',
    'ON_TIME',
    'GOOD_COMMUNICATION',
  ];

  static const negativeCodes = [
    'UNSAFE_DRIVING',
    'LATE_ARRIVAL',
    'VEHICLE_NOT_CLEAN',
    'UNFRIENDLY_SERVICE',
    'ROUTE_ISSUE',
    'OTHER_ISSUE',
  ];

  static String labelKey(String code) => 'review_tag_$code';

  static List<String> visibleCodes(int? rating) {
    if (rating == null || rating <= 0) return const [];
    if (rating <= 2) return [...positiveCodes, ...negativeCodes];
    return positiveCodes;
  }

  static Set<String> allowedCodes(int rating) => visibleCodes(rating).toSet();

  static List<String> sanitizeSelection(int rating, Iterable<String> selected) {
    final allowed = allowedCodes(rating);
    final seen = <String>{};
    final result = <String>[];
    for (final raw in selected) {
      final code = raw.trim().toUpperCase();
      if (!allowed.contains(code) || seen.contains(code)) continue;
      seen.add(code);
      result.add(code);
    }
    return result;
  }
}

String reviewRatingDescriptionKey(int rating) => 'review_rating_desc_$rating';
