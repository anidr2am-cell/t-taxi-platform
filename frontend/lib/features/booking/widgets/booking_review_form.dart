import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/user_facing_error.dart';
import '../../../l10n/app_localizations.dart';
import '../../../config/app_config.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../utils/review_tags.dart';

class BookingReviewApi {
  const BookingReviewApi();

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  static String guestTokenKey(String bookingNumber) =>
      'guest_access_token_$bookingNumber';

  Future<void> persistGuestToken(String bookingNumber, String? token) async {
    if (token == null || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(guestTokenKey(bookingNumber), token);
  }

  Future<String?> loadGuestToken(String bookingNumber) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(guestTokenKey(bookingNumber));
  }

  Future<Map<String, dynamic>> getReview({
    required String bookingNumber,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final uri = Uri.parse('$_base/bookings/$bookingNumber/review');
    final headers = <String, String>{'Accept': 'application/json'};
    if (customerAccessToken != null && customerAccessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerAccessToken';
    }
    if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      headers['X-Guest-Access-Token'] = guestAccessToken;
    }
    final response = await http.get(uri, headers: headers);
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      throw BookingReviewApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
        code,
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }

  Future<Map<String, dynamic>> submitReview({
    required String bookingNumber,
    required int rating,
    List<String>? tags,
    String? comment,
    String? guestAccessToken,
    String? customerAccessToken,
  }) async {
    final uri = Uri.parse('$_base/bookings/$bookingNumber/review');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (customerAccessToken != null && customerAccessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerAccessToken';
    }
    final body = <String, dynamic>{'rating': rating};
    if (tags != null && tags.isNotEmpty) body['tags'] = tags;
    if (comment != null && comment.isNotEmpty) body['comment'] = comment;
    if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      body['guestAccessToken'] = guestAccessToken;
    }
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      throw BookingReviewApiException(
        decoded is Map
            ? decoded['message'] as String? ?? 'Request failed'
            : 'Request failed',
        code,
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }
}

class BookingReviewApiException implements Exception {
  const BookingReviewApiException(this.message, [this.errorCode]);
  final String message;
  final String? errorCode;
  @override
  String toString() => message;
}

bool isValidReviewRating(int? rating) => rating != null && rating >= 1 && rating <= 5;

class BookingReviewForm extends StatefulWidget {
  const BookingReviewForm({
    super.key,
    required this.bookingNumber,
    this.guestAccessToken,
    this.api,
    this.initialState,
  });

  final String bookingNumber;
  final String? guestAccessToken;
  final BookingReviewApi? api;
  final Map<String, dynamic>? initialState;

  @override
  State<BookingReviewForm> createState() => BookingReviewFormState();
}

class BookingReviewFormState extends State<BookingReviewForm> {
  late final BookingReviewApi _api = widget.api ?? const BookingReviewApi();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _state;
  int? _rating;
  final Set<String> _selectedTags = {};
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialState != null) {
      _state = widget.initialState;
      _loading = false;
    } else {
      _load();
    }
    _commentController.addListener(_onCommentChanged);
  }

  void _onCommentChanged() => setState(() {});

  @override
  void dispose() {
    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token =
          widget.guestAccessToken ?? await _api.loadGuestToken(widget.bookingNumber);
      final state = await _api.getReview(
        bookingNumber: widget.bookingNumber,
        guestAccessToken: token,
      );
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('booking_review_load_error'),
        );
        _loading = false;
      });
    }
  }

  void _setRating(int value) {
    if (_submitting) return;
    setState(() {
      _rating = value;
      _selectedTags.retainAll(ReviewTags.allowedCodes(value));
    });
  }

  void _toggleTag(String code) {
    if (_submitting || _rating == null) return;
    setState(() {
      if (_selectedTags.contains(code)) {
        _selectedTags.remove(code);
      } else {
        _selectedTags.add(code);
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting || !isValidReviewRating(_rating)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final token =
          widget.guestAccessToken ?? await _api.loadGuestToken(widget.bookingNumber);
      final tags = ReviewTags.sanitizeSelection(_rating!, _selectedTags);
      final comment = _commentController.text.trim();
      final state = await _api.submitReview(
        bookingNumber: widget.bookingNumber,
        rating: _rating!,
        tags: tags,
        comment: comment.isEmpty ? null : comment,
        guestAccessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _state = state;
        _submitting = false;
      });
    } catch (err) {
      if (err is BookingReviewApiException &&
          err.errorCode == 'REVIEW_ALREADY_SUBMITTED') {
        await _load();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
        _submitting = false;
      });
    }
  }

  List<String> _submittedTags() {
    final raw = _state?['tags'];
    if (raw is List) {
      return raw.map((item) => item.toString()).toList();
    }
    return const [];
  }

  Widget _buildStarRow(AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final value = index + 1;
        final filled = value <= (_rating ?? 0);
        return Semantics(
          button: true,
          label: l10n.t('review_star_label').replaceAll('{value}', '$value'),
          child: SizedBox(
            width: 52,
            height: 52,
            child: InkWell(
              key: ValueKey('review_rating_$value'),
              borderRadius: BorderRadius.circular(12),
              onTap: _submitting ? null : () => _setRating(value),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: Colors.amber.shade700,
                size: 38,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTagChips(AppLocalizations l10n) {
    final codes = ReviewTags.visibleCodes(_rating);
    if (codes.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: codes.map((code) {
        final selected = _selectedTags.contains(code);
        return FilterChip(
          key: ValueKey('review_tag_$code'),
          label: Text(l10n.t(ReviewTags.labelKey(code))),
          selected: selected,
          onSelected: _submitting ? null : (_) => _toggleTag(code),
        );
      }).toList(),
    );
  }

  Widget _buildSubmittedCard(AppLocalizations l10n) {
    final rating = _state?['rating'];
    final tags = _submittedTags();
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.successLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('review_success_title'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: AppTokens.success,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.t('review_success_body'),
            style: const TextStyle(color: AppTokens.textSecondary, height: 1.45),
          ),
          if (rating != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              children: List.generate(5, (index) {
                final value = index + 1;
                return Icon(
                  value <= (rating as num).toInt()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber.shade700,
                  size: 22,
                );
              }),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map(
                    (code) => Chip(
                      label: Text(l10n.t(ReviewTags.labelKey(code))),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && (_state == null)) {
      return Column(
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: Text(l10n.t('driver_retry'))),
        ],
      );
    }

    final eligible = _state?['eligible'] == true;
    final submitted = _state?['submitted'] == true;
    if (!eligible) return const SizedBox.shrink();
    if (submitted) return _buildSubmittedCard(l10n);

    final commentLength = _commentController.text.length;

    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('review_card_title'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.t('review_card_subtitle'),
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _buildStarRow(l10n),
          if (isValidReviewRating(_rating)) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.t(reviewRatingDescriptionKey(_rating!)),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTokens.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          _buildTagChips(l10n),
          const SizedBox(height: AppTokens.spaceMd),
          TextField(
            controller: _commentController,
            maxLength: 500,
            maxLines: 4,
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: l10n.t('review_comment_label'),
              helperText: l10n.t('review_comment_hint'),
              counterText: '$commentLength/500',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.primaryButton(
            label: l10n.t('review_submit_button'),
            icon: Icons.check_circle_outline,
            loading: _submitting,
            onPressed: _submitting || !isValidReviewRating(_rating) ? null : _submit,
          ),
        ],
      ),
    );
  }
}
