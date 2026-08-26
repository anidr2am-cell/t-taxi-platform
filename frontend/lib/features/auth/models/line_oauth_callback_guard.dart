import 'dart:convert';

import 'social_login_return_context.dart';

enum LineOAuthCallbackOutcome { pending, success, failure }

class LineOAuthCallbackGuardRecord {
  const LineOAuthCallbackGuardRecord({
    required this.code,
    required this.outcome,
    this.returnContext,
  });

  final String code;
  final LineOAuthCallbackOutcome outcome;
  final SocialLoginReturnContext? returnContext;

  bool get isSuccess => outcome == LineOAuthCallbackOutcome.success;

  bool get isFailure => outcome == LineOAuthCallbackOutcome.failure;

  bool get isPending => outcome == LineOAuthCallbackOutcome.pending;
}

abstract class LineOAuthCallbackGuardStorage {
  static const processedCodeKey = 'line_processed_code';
  static const processedOutcomeKey = 'line_processed_outcome';
  static const processedReturnContextKey = 'line_processed_return_context';

  Future<LineOAuthCallbackGuardRecord?> load();

  Future<void> save(LineOAuthCallbackGuardRecord record);

  Future<void> clear();
}

LineOAuthCallbackGuardRecord? decodeLineOAuthCallbackGuardRecord(
  Map<String, String> values,
) {
  final code = values[LineOAuthCallbackGuardStorage.processedCodeKey]?.trim();
  if (code == null || code.isEmpty) {
    return null;
  }

  final outcomeRaw =
      values[LineOAuthCallbackGuardStorage.processedOutcomeKey]?.trim();
  LineOAuthCallbackOutcome? outcome;
  for (final candidate in LineOAuthCallbackOutcome.values) {
    if (candidate.name == outcomeRaw) {
      outcome = candidate;
      break;
    }
  }
  if (outcome == null) {
    return null;
  }

  final contextRaw =
      values[LineOAuthCallbackGuardStorage.processedReturnContextKey];
  SocialLoginReturnContext? returnContext;
  if (contextRaw != null && contextRaw.isNotEmpty) {
    try {
      returnContext = SocialLoginReturnContext.fromJson(
        Map<String, dynamic>.from(jsonDecode(contextRaw) as Map),
      );
    } catch (_) {
      returnContext = null;
    }
  }

  return LineOAuthCallbackGuardRecord(
    code: code,
    outcome: outcome,
    returnContext: returnContext,
  );
}

Map<String, String> encodeLineOAuthCallbackGuardRecord(
  LineOAuthCallbackGuardRecord record,
) {
  final values = <String, String>{
    LineOAuthCallbackGuardStorage.processedCodeKey: record.code,
    LineOAuthCallbackGuardStorage.processedOutcomeKey: record.outcome.name,
  };
  if (record.returnContext != null) {
    values[LineOAuthCallbackGuardStorage.processedReturnContextKey] =
        jsonEncode(record.returnContext!.toJson());
  }
  return values;
}

String? parseLineAuthorizationCode(Uri uri) {
  final code = uri.queryParameters['code']?.trim();
  if (code == null || code.isEmpty) {
    return null;
  }
  return code;
}

String? parseLineAuthorizationState(Uri uri) {
  final state = uri.queryParameters['state']?.trim();
  if (state == null || state.isEmpty) {
    return null;
  }
  return state;
}

String? parseLineAuthorizationError(Uri uri) {
  final error = uri.queryParameters['error']?.trim();
  if (error == null || error.isEmpty) {
    return null;
  }
  final description = uri.queryParameters['error_description']?.trim();
  if (description == null || description.isEmpty) {
    return error;
  }
  return '$error: $description';
}
