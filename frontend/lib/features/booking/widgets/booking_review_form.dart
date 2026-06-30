import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/user_facing_error.dart';
import '../../../config/app_config.dart';

class BookingReviewApi {
  const BookingReviewApi();

  String get _base => '${AppConfig.apiBaseUrl}/api/v1';

  static String guestTokenKey(String bookingNumber) => 'guest_access_token_$bookingNumber';

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
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
        code,
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['data'] as Map);
  }

  Future<Map<String, dynamic>> submitReview({
    required String bookingNumber,
    required int rating,
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
    if (comment != null) body['comment'] = comment;
    if (guestAccessToken != null && guestAccessToken.isNotEmpty) {
      body['guestAccessToken'] = guestAccessToken;
    }
    final response = await http.post(uri, headers: headers, body: jsonEncode(body));
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final code = decoded is Map ? decoded['error_code'] as String? : null;
      throw BookingReviewApiException(
        decoded is Map ? decoded['message'] as String? ?? 'Request failed' : 'Request failed',
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
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = widget.guestAccessToken ?? await _api.loadGuestToken(widget.bookingNumber);
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
        _error = userFacingError(err, fallback: 'Could not load review');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || !isValidReviewRating(_rating)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final token = widget.guestAccessToken ?? await _api.loadGuestToken(widget.bookingNumber);
      final state = await _api.submitReview(
        bookingNumber: widget.bookingNumber,
        rating: _rating!,
        comment: _commentController.text.trim(),
        guestAccessToken: token,
      );
      setState(() {
        _state = state;
        _submitting = false;
      });
    } catch (err) {
      if (err is BookingReviewApiException && err.errorCode == 'REVIEW_ALREADY_SUBMITTED') {
        await _load();
        return;
      }
      setState(() {
        _error = userFacingError(err, fallback: 'Could not load review');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_state == null)) {
      return Column(
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }

    final eligible = _state?['eligible'] == true;
    final submitted = _state?['submitted'] == true;
    if (!eligible) return const SizedBox.shrink();

    if (submitted) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Thank you for your review', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Rating: ${_state?['rating']} / 5'),
              if (_state?['comment'] != null) Text('${_state?['comment']}'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Rate your trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final value = index + 1;
                return IconButton(
                  key: ValueKey('review_rating_$value'),
                  onPressed: _submitting ? null : () => setState(() => _rating = value),
                  icon: Icon(
                    value <= (_rating ?? 0) ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                );
              }),
            ),
            TextField(
              controller: _commentController,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Comment (optional)'),
              enabled: !_submitting,
            ),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            ElevatedButton(
              onPressed: _submitting || !isValidReviewRating(_rating) ? null : _submit,
              child: Text(_submitting ? 'Submitting...' : 'Submit review'),
            ),
            if (_error != null)
              OutlinedButton(
                onPressed: _submitting ? null : _submit,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}
